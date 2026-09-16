import Foundation
import Observation

/// Sync between the user's own Macs through iCloud Drive, off unless they
/// turn it on and choose a passphrase.
///
/// What travels: snippets, custom writing modes, app & website settings,
/// custom instructions, My Info — and writing samples only with a second,
/// separate opt-in. Never screenshots, OCR, the clipboard, logs, stats, the
/// style buffer or model files.
///
/// Everything is encrypted on this Mac before it is written
/// (`SyncCrypto`: PBKDF2-SHA256 → AES-GCM), so iCloud Drive stores a blob it
/// cannot read. Merging is per item, last edit wins, with a device id as the
/// tie-break; deletions travel as tombstones that expire after 30 days.
///
/// With sync off, nothing here touches `~/Library/Mobile Documents` at all.
@MainActor
@Observable
final class SyncManager {
    static let shared = SyncManager()

    enum Status: Equatable, Sendable {
        case off
        case unavailable
        case idle(lastSync: Date?)
        case syncing
        /// The cloud copy hasn't been downloaded to this Mac yet.
        case waitingForDownload
        case error(SyncErrorKind)
    }

    private(set) var status: Status = .off
    private(set) var lastSyncAt: Date?

    // MARK: Constants

    nonisolated static let keychainService = "com.qalamai.app.sync"
    nonisolated static let keychainAccount = "passphrase-v1"
    nonisolated static let folderName = Constants.appName
    nonisolated static let settingsBaseName = "qalam-sync-v1"
    nonisolated static let personalizationBaseName = "qalam-personalization-v1"
    nonisolated static let fileExtension = "qsync"
    nonisolated static let payloadVersion = 1
    static let minPassphraseLength = 8

    private static let pullIntervalSeconds: TimeInterval = 15 * 60
    private static let firstPullDelayNs: UInt64 = 10_000_000_000
    private static let pushDebounceNs: UInt64 = 5_000_000_000
    private static let folderChangeDebounceNs: UInt64 = 3_000_000_000
    /// How long our own writes keep the folder watcher quiet.
    private static let selfWriteQuiet: TimeInterval = 5

    private static let lastSyncKey = "qalam.sync.lastSyncAt"

    // MARK: Paths

    /// `~/Library/Mobile Documents/com~apple~CloudDocs`. Only ever touched
    /// when the user asked for sync (or opened the Sync tab).
    nonisolated static var cloudRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    nonisolated static var cloudFolder: URL {
        cloudRoot.appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated static var settingsURL: URL {
        cloudFolder.appendingPathComponent("\(settingsBaseName).\(fileExtension)")
    }

    nonisolated static var personalizationURL: URL {
        cloudFolder.appendingPathComponent("\(personalizationBaseName).\(fileExtension)")
    }

    /// 0600 fallback for the passphrase, used only when the keychain refuses.
    nonisolated static var passphraseFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Constants.appSupportDirName, isDirectory: true)
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent(".passphrase")
    }

    /// iCloud Drive is switched on for this Mac. A file-system check, done
    /// lazily — never at launch with sync off.
    nonisolated static func cloudDriveAvailable() -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: cloudRoot.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// True when this Mac has ever enabled sync (the uninstaller uses it to
    /// decide whether to look in iCloud Drive at all).
    nonisolated static var everEnabled: Bool { SyncMetadata.storedDeviceID != nil }

    // MARK: State

    @ObservationIgnored private let io = SyncFileIO.shared
    @ObservationIgnored private var passphrase: String?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var isSyncing = false
    /// Set after a wrong passphrase: no push until the user re-enters it.
    @ObservationIgnored private var pushSuspended = false
    @ObservationIgnored private var pullTimer: Timer?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var folderTask: Task<Void, Never>?
    @ObservationIgnored private var firstPullTask: Task<Void, Never>?
    @ObservationIgnored private var metadataObserver: NSObjectProtocol?
    @ObservationIgnored private var watchSource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var quietUntil = Date.distantPast
    /// Bumped by `stopActivity()`. A cycle that is already running is not
    /// owned by any of the tasks that cancels, so it carries the epoch it
    /// started with and checks it after every await — see `cycleIsStale`.
    @ObservationIgnored private var cycleEpoch = 0

    private init() {
        let raw = QalamDefaults.suite.double(forKey: Self.lastSyncKey)
        lastSyncAt = raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    // MARK: - Lifecycle

    /// Called once at launch, after the stores exist. Does nothing at all
    /// while sync is off.
    func start() {
        guard !started else { return }
        started = true
        guard UserPreferences.shared.syncEnabled else {
            status = .off
            return
        }
        SyncMetadata.shared.pruneTombstones()
        status = .idle(lastSync: lastSyncAt)
        beginObserving()
        firstPullTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.firstPullDelayNs)
            guard !Task.isCancelled else { return }
            await self?.performSync(reason: "launch")
        }
        QLog.notice(.sync, "sync enabled — first pull in 10 s")
    }

    /// Stops every timer and watcher (quit / uninstall / sync turned off),
    /// and retires any cycle that is already in flight.
    func stopActivity() {
        cycleEpoch &+= 1
        firstPullTask?.cancel(); firstPullTask = nil
        pushTask?.cancel(); pushTask = nil
        folderTask?.cancel(); folderTask = nil
        pullTimer?.invalidate(); pullTimer = nil
        watchSource?.cancel(); watchSource = nil
        if let observer = metadataObserver {
            NotificationCenter.default.removeObserver(observer)
            metadataObserver = nil
        }
    }

    private func beginObserving() {
        stopActivity()
        pullTimer = Timer.scheduledTimer(withTimeInterval: Self.pullIntervalSeconds,
                                         repeats: true) { _ in
            Task { @MainActor in await SyncManager.shared.performSync(reason: "timer") }
        }
        metadataObserver = NotificationCenter.default.addObserver(
            forName: SyncMetadata.didChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SyncManager.shared.schedulePush() }
        }
        startWatchingFolder()
    }

    // MARK: - Public actions

    /// Turns sync on. Returns nil on success, otherwise why it failed —
    /// nothing is enabled and no remote file is touched when it fails.
    func enable(passphrase raw: String) async -> SyncErrorKind? {
        let pass = raw
        guard pass.count >= Self.minPassphraseLength else { return .wrongPassphrase }
        guard Self.cloudDriveAvailable() else {
            status = .unavailable
            return .io
        }
        guard await io.ensureFolder(Self.cloudFolder) else { return .io }

        // An existing cloud copy has to open with this passphrase, or we stop
        // right here — overwriting it would destroy the other Mac's data.
        var remoteKeys: Set<String> = []
        var remoteExists = false
        switch await io.readPayload(at: Self.settingsURL, passphrase: pass) {
        case .missing:
            break
        case .notDownloaded:
            // The copy is in iCloud but not on this Mac yet. Enabling now
            // could push over it, so wait and let the user try again.
            return .io
        case .payload(let payload):
            remoteExists = true
            remoteKeys = Set(payload.items.map(\.key))
        case .failure(let kind):
            if UserPreferences.shared.syncEnabled { status = .error(kind) }
            return kind
        }

        guard await storePassphrase(pass) else {
            return .keychainUnavailable
        }
        self.passphrase = pass
        pushSuspended = false

        let meta = SyncMetadata.shared
        meta.ensureDeviceID()
        // Items that were never edited are `.distantPast`, so they lose to
        // anything already in iCloud. Give a real date only to the ones the
        // cloud copy doesn't have yet — that way a Mac joining later adds
        // what is missing instead of overwriting what is there.
        let now = Date()
        for key in gatherSettings().keys where !remoteExists || !remoteKeys.contains(key) {
            meta.stampIfUnset(key, at: now)
        }

        UserPreferences.shared.syncEnabled = true
        beginObserving()
        await performSync(reason: "enable")
        QLog.notice(.sync, "sync turned on (cloud copy existed: \(remoteExists))")
        return nil
    }

    func syncNow() async {
        await performSync(reason: "manual")
    }

    /// Turns sync off on this Mac. The cloud copy stays unless the user asked
    /// for it to go to the Trash (from where it is recoverable for 30 days).
    func disable(removeCloudCopy: Bool) {
        UserPreferences.shared.syncEnabled = false
        stopActivity()
        passphrase = nil
        pushSuspended = false
        status = .off
        Task.detached {
            KeychainHelper.delete(service: SyncManager.keychainService,
                                  account: SyncManager.keychainAccount)
            if let file = SyncManager.passphraseFileURL {
                try? FileManager.default.removeItem(at: file)
            }
        }
        if removeCloudCopy {
            let folder = Self.cloudFolder
            SyncMetadata.shared.reset()
            Task { await SyncFileIO.shared.trash([folder]) }
        }
        QLog.notice(.sync, "sync turned off (cloud copy removed: \(removeCloudCopy))")
    }

    // MARK: - Passphrase

    private func storePassphrase(_ pass: String) async -> Bool {
        let file = Self.passphraseFileURL
        return await Task.detached { () -> Bool in
            let data = Data(pass.utf8)
            if KeychainHelper.write(data, service: SyncManager.keychainService,
                                    account: SyncManager.keychainAccount) {
                return true
            }
            QLog.notice(.sync, "keychain unavailable — passphrase kept in a 0600 file")
            guard let file else { return false }
            return SecretFile.write(data, to: file)
        }.value
    }

    private func loadPassphrase() async -> String? {
        if let passphrase { return passphrase }
        let file = Self.passphraseFileURL
        let found = await Task.detached { () -> String? in
            switch KeychainHelper.read(service: SyncManager.keychainService,
                                       account: SyncManager.keychainAccount) {
            case .found(let data):
                return String(data: data, encoding: .utf8)
            case .notFound, .failed:
                guard let file, let data = SecretFile.read(file) else { return nil }
                return String(data: data, encoding: .utf8)
            }
        }.value
        passphrase = found
        return found
    }

    // MARK: - The cycle

    /// True once this cycle has been retired — the user turned sync off, quit
    /// or uninstalled while it was suspended in an await. Everything after
    /// such a check must return without writing to the stores, to the
    /// metadata, to iCloud Drive or to `status` (`disable()` already set it).
    private func cycleIsStale(_ epoch: Int) -> Bool {
        epoch != cycleEpoch || !UserPreferences.shared.syncEnabled
    }

    private func performSync(reason: String) async {
        guard UserPreferences.shared.syncEnabled else { status = .off; return }
        guard !isSyncing, !pushSuspended else { return }
        guard Self.cloudDriveAvailable() else {
            status = .unavailable
            return
        }
        let epoch = cycleEpoch
        let loaded = await loadPassphrase()
        // Bail out before `ensureFolder`, or turning sync off with "remove the
        // cloud copy" would race this cycle into re-creating the folder it
        // just sent to the Trash.
        guard !cycleIsStale(epoch) else { return }
        guard let pass = loaded else {
            status = .error(.keychainUnavailable)
            return
        }
        let folderReady = await io.ensureFolder(Self.cloudFolder)
        guard !cycleIsStale(epoch) else { return }
        guard folderReady else {
            status = .error(.io)
            return
        }

        isSyncing = true
        status = .syncing
        defer { isSyncing = false }

        SyncMetadata.shared.pruneTombstones()
        var failure: SyncErrorKind?
        var waiting = false

        switch await syncSettings(passphrase: pass, epoch: epoch) {
        case .ok:            break
        case .waiting:       waiting = true
        case .failed(let k): failure = k
        case .cancelled:     return
        }

        if failure == nil, UserPreferences.shared.syncIncludePersonalization {
            switch await syncSamples(passphrase: pass, epoch: epoch) {
            case .ok:            break
            case .waiting:       waiting = true
            case .failed(let k): failure = k
            case .cancelled:     return
            }
        }

        guard !cycleIsStale(epoch) else { return }
        if let failure {
            if failure == .wrongPassphrase { pushSuspended = true }
            status = .error(failure)
            QLog.error(.sync, "sync failed (\(reason))")
            return
        }
        if waiting {
            status = .waitingForDownload
            return
        }
        let now = Date()
        lastSyncAt = now
        QalamDefaults.suite.set(now.timeIntervalSince1970, forKey: Self.lastSyncKey)
        status = .idle(lastSync: now)
        QLog.info(.sync, "sync finished (\(reason))")
    }

    private enum CycleResult {
        case ok
        case waiting
        case failed(SyncErrorKind)
        /// Sync was turned off (or the app is quitting) mid-cycle.
        case cancelled
    }

    // MARK: Settings bundle

    private func syncSettings(passphrase pass: String, epoch: Int) async -> CycleResult {
        let url = Self.settingsURL
        var remoteItems: [SyncItem] = []
        var remoteExisted = false

        switch await io.readPayload(at: url, passphrase: pass) {
        case .missing:            break
        case .notDownloaded:      return .waiting
        case .failure(let kind):  return .failed(kind)
        case .payload(let p):
            remoteExisted = true
            remoteItems = p.items
        }
        guard !cycleIsStale(epoch) else { return .cancelled }

        // iCloud leaves "… 2.qsync" behind when two Macs wrote at once.
        // Merge those in before they are moved to the Trash.
        let conflicts = await io.conflictCopies(in: Self.cloudFolder,
                                                baseName: Self.settingsBaseName,
                                                fileExtension: Self.fileExtension)
        var mergedConflicts: [URL] = []
        for copy in conflicts {
            if case .payload(let p) = await io.readPayload(at: copy, passphrase: pass) {
                remoteItems.append(contentsOf: p.items)
                mergedConflicts.append(copy)
            }
        }
        // Last check before anything is written: from here to `writePayload`
        // there is no other suspension point, so this one guard covers the
        // local stores, the metadata and the cloud file.
        guard !cycleIsStale(epoch) else { return .cancelled }

        let local = gatherSettings()
        let outcome = SyncMerge.merge(local: local, remote: remoteItems,
                                      tombstoneCutoff: Date().addingTimeInterval(-SyncMetadata.tombstoneLifetime))
        if !outcome.toApply.isEmpty { applySettings(outcome.toApply) }

        let remoteDict = SyncMerge.dictionary(remoteItems)
        let needsPush = outcome.merged != remoteDict || !remoteExisted || !mergedConflicts.isEmpty
        if needsPush {
            let payload = SyncPayload(version: Self.payloadVersion,
                                      deviceID: SyncMetadata.shared.ensureDeviceID(),
                                      items: outcome.merged.values.sorted { $0.key < $1.key })
            quietUntil = Date().addingTimeInterval(Self.selfWriteQuiet)
            if let kind = await io.writePayload(payload, to: url, passphrase: pass) {
                return .failed(kind)
            }
            QLog.info(.sync, "pushed \(payload.items.count) setting item(s)")
            if !mergedConflicts.isEmpty { await io.trash(mergedConflicts) }
        }
        return .ok
    }

    /// Everything this Mac would put in the settings file right now.
    private func gatherSettings() -> [String: SyncItem] {
        let meta = SyncMetadata.shared
        let device = meta.deviceID
        let encoder = JSONEncoder()
        var out: [String: SyncItem] = [:]

        func put(_ key: String, _ payload: Data?) {
            guard let payload else { return }
            let entry = meta.entry(key)
            out[key] = SyncItem(key: key,
                                modifiedAt: entry?.modifiedAt ?? .distantPast,
                                deviceID: entry?.deviceID ?? device,
                                deleted: false,
                                payload: payload)
        }

        for snippet in SnippetStore.shared.snippets {
            put(SyncKey.snippet(snippet.trigger), try? encoder.encode(snippet))
        }
        for mode in WritingModeStore.shared.customModes {
            put(SyncKey.mode(mode.id), try? encoder.encode(mode))
        }
        for profile in ProfileStore.shared.profiles where profile.isConfigured {
            // `lastSeen` is this Mac's own bookkeeping — normalised out so it
            // never causes a push.
            var shared = profile
            shared.lastSeen = .distantPast
            // So is `displayName`: it is this Mac's LaunchServices lookup, in
            // this Mac's language, not a setting the user chose. Left in, two
            // Macs disagree about the bytes ("Slack" vs the bundle id on a Mac
            // that doesn't have it installed), the merge tie-breaks on length
            // and the pair flip-flops forever. `applySyncItems` resolves a
            // local name on the way back in.
            shared.displayName = profile.key
            put(SyncKey.profile(profile.id), try? encoder.encode(shared))
        }
        for item in PersonalInfoStore.shared.items
        where !item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            put(SyncKey.myInfo(item.id), try? encoder.encode(item))
        }
        // Only when there is something to say: an empty field on one Mac
        // must never overwrite real instructions on another.
        let instructions = UserPreferences.shared.customInstructions
        if !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            put(SyncKey.customInstructions, Data(instructions.utf8))
        }

        for (key, entry) in meta.entries where entry.deleted && SyncKey.isSettings(key) {
            guard out[key] == nil else { continue }
            out[key] = SyncItem(key: key, modifiedAt: entry.modifiedAt,
                                deviceID: entry.deviceID, deleted: true, payload: nil)
        }
        return out
    }

    /// Writes the winners into the stores. Hooks are muted throughout, so
    /// applying a pull never looks like a local edit.
    private func applySettings(_ winners: [SyncItem]) {
        let meta = SyncMetadata.shared
        meta.isApplyingRemote = true
        defer { meta.isApplyingRemote = false }

        let decoder = JSONDecoder()
        var snippetUps: [Snippet] = [];         var snippetDels: [String] = []
        var modeUps: [WritingMode] = [];        var modeDels: [String] = []
        var profileUps: [AppProfile] = [];      var profileDels: [String] = []
        var infoUps: [PersonalInfoItem] = [];   var infoDels: [String] = []
        var instructions: String?
        var applied: [SyncItem] = []

        for item in winners {
            switch item.key {
            case let key where key.hasPrefix(SyncKey.snippetPrefix):
                let trigger = SyncKey.value(key, prefix: SyncKey.snippetPrefix)
                if item.deleted {
                    snippetDels.append(trigger)
                } else if let data = item.payload,
                          let snippet = try? decoder.decode(Snippet.self, from: data) {
                    snippetUps.append(snippet)
                } else { continue }

            case let key where key.hasPrefix(SyncKey.modePrefix):
                let id = SyncKey.value(key, prefix: SyncKey.modePrefix)
                if item.deleted {
                    modeDels.append(id)
                } else if let data = item.payload,
                          let mode = try? decoder.decode(WritingMode.self, from: data) {
                    modeUps.append(mode)
                } else { continue }

            case let key where key.hasPrefix(SyncKey.profilePrefix):
                let id = SyncKey.value(key, prefix: SyncKey.profilePrefix)
                if item.deleted {
                    profileDels.append(id)
                } else if let data = item.payload,
                          let profile = try? decoder.decode(AppProfile.self, from: data),
                          profile.id == id {
                    profileUps.append(profile)
                } else { continue }

            case let key where key.hasPrefix(SyncKey.myInfoPrefix):
                let id = SyncKey.value(key, prefix: SyncKey.myInfoPrefix)
                if item.deleted {
                    infoDels.append(id)
                } else if let data = item.payload,
                          let info = try? decoder.decode(PersonalInfoItem.self, from: data) {
                    infoUps.append(info)
                } else { continue }

            case SyncKey.customInstructions:
                if item.deleted {
                    instructions = ""
                } else if let data = item.payload, let text = String(data: data, encoding: .utf8) {
                    instructions = text
                } else { continue }

            default:
                continue   // an item kind this build doesn't know
            }
            applied.append(item)
        }

        if !snippetUps.isEmpty || !snippetDels.isEmpty {
            SnippetStore.shared.applySyncItems(snippetUps, deletions: snippetDels)
        }
        if !modeUps.isEmpty || !modeDels.isEmpty {
            WritingModeStore.shared.applySyncItems(modeUps, deletions: modeDels)
        }
        if !profileUps.isEmpty || !profileDels.isEmpty {
            ProfileStore.shared.applySyncItems(profileUps, deletions: profileDels)
        }
        if !infoUps.isEmpty || !infoDels.isEmpty {
            PersonalInfoStore.shared.applySyncItems(infoUps, deletions: infoDels)
        }
        if let instructions, instructions != UserPreferences.shared.customInstructions {
            UserPreferences.shared.customInstructions =
                String(instructions.prefix(ProfileStore.globalInstructionsLimit))
        }

        // Remember exactly what we took, so the next gather reproduces it
        // instead of pushing it straight back.
        for item in applied {
            meta.record(item.key, modifiedAt: item.modifiedAt,
                        deviceID: item.deviceID, deleted: item.deleted)
        }
        QLog.info(.sync, "applied \(applied.count) item(s) from the cloud copy")
    }

    // MARK: Writing samples

    private func syncSamples(passphrase pass: String, epoch: Int) async -> CycleResult {
        let store = PersonalizationStore.shared
        await store.loadIfNeeded()
        guard let samples = await store.syncSnapshot() else { return .ok }   // store unavailable
        guard !cycleIsStale(epoch) else { return .cancelled }

        let url = Self.personalizationURL
        var remoteItems: [SyncItem] = []
        var remoteExisted = false
        switch await io.readPayload(at: url, passphrase: pass) {
        case .missing:            break
        case .notDownloaded:      return .waiting
        case .failure(let kind):  return .failed(kind)
        case .payload(let p):
            remoteExisted = true
            remoteItems = p.items
        }
        // Nothing below may write into the sample store or its metadata once
        // the user has turned sync off.
        guard !cycleIsStale(epoch) else { return .cancelled }

        let local = gatherSamples(samples)
        let outcome = SyncMerge.merge(local: local, remote: remoteItems,
                                      tombstoneCutoff: Date().addingTimeInterval(-SyncMetadata.tombstoneLifetime))

        if !outcome.toApply.isEmpty {
            let decoder = JSONDecoder()
            var upserts: [WritingSample] = []
            var deletions: [String] = []
            var tombstones: [SyncItem] = []
            for item in outcome.toApply where SyncKey.isSample(item.key) {
                let id = SyncKey.value(item.key, prefix: SyncKey.samplePrefix)
                if item.deleted {
                    deletions.append(id)
                    tombstones.append(item)
                } else if let data = item.payload,
                          let sample = try? decoder.decode(WritingSample.self, from: data) {
                    upserts.append(sample)
                }
            }
            if !upserts.isEmpty || !deletions.isEmpty {
                await store.applySyncSamples(upserts, deletions: deletions)
            }
            let meta = SyncMetadata.shared
            meta.isApplyingRemote = true
            for item in tombstones {
                meta.record(item.key, modifiedAt: item.modifiedAt,
                            deviceID: item.deviceID, deleted: true)
            }
            meta.isApplyingRemote = false
        }

        // `applySyncSamples` above suspends, so re-check before the push.
        guard !cycleIsStale(epoch) else { return .cancelled }

        let remoteDict = SyncMerge.dictionary(remoteItems)
        if outcome.merged != remoteDict || !remoteExisted {
            let payload = SyncPayload(version: Self.payloadVersion,
                                      deviceID: SyncMetadata.shared.ensureDeviceID(),
                                      items: outcome.merged.values.sorted { $0.key < $1.key })
            quietUntil = Date().addingTimeInterval(Self.selfWriteQuiet)
            if let kind = await io.writePayload(payload, to: url, passphrase: pass) {
                return .failed(kind)
            }
            QLog.info(.sync, "pushed \(payload.items.count) writing sample item(s)")
        }
        return .ok
    }

    /// Samples never change once written, so their date is their version and
    /// the device id plays no part — a constant keeps both Macs' files
    /// byte-identical instead of ping-ponging one field.
    private func gatherSamples(_ samples: [WritingSample]) -> [String: SyncItem] {
        let meta = SyncMetadata.shared
        let encoder = JSONEncoder()
        var out: [String: SyncItem] = [:]
        for sample in samples {
            guard let payload = try? encoder.encode(sample) else { continue }
            out[SyncKey.sample(sample.id)] = SyncItem(key: SyncKey.sample(sample.id),
                                                      modifiedAt: sample.date,
                                                      deviceID: "",
                                                      deleted: false,
                                                      payload: payload)
        }
        for (key, entry) in meta.entries where entry.deleted && SyncKey.isSample(key) {
            guard out[key] == nil else { continue }
            out[key] = SyncItem(key: key, modifiedAt: entry.modifiedAt,
                                deviceID: entry.deviceID, deleted: true, payload: nil)
        }
        return out
    }

    // MARK: - Triggers

    private func schedulePush() {
        guard UserPreferences.shared.syncEnabled, !pushSuspended else { return }
        pushTask?.cancel()
        pushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.pushDebounceNs)
            guard !Task.isCancelled else { return }
            await self?.performSync(reason: "local change")
        }
    }

    /// Watches `<iCloud Drive>/QalamAI` so another Mac's push is picked up
    /// without waiting for the 15-minute timer.
    private func startWatchingFolder() {
        guard Self.cloudDriveAvailable() else { return }
        let path = Self.cloudFolder.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { SyncManager.shared.folderChanged() }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        watchSource = source
    }

    private func folderChanged() {
        // Ignore the echo of our own push.
        guard Date() >= quietUntil else { return }
        folderTask?.cancel()
        folderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.folderChangeDebounceNs)
            guard !Task.isCancelled else { return }
            await self?.performSync(reason: "cloud change")
        }
    }
}
