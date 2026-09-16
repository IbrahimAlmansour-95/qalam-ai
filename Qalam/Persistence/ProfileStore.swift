import Foundation
import AppKit
import Observation

/// Per-app and per-website settings, and the single place that turns them
/// into effective settings (`resolve`).
///
/// Resolution, per field: the most specific matching site profile (longest
/// host suffix on a label boundary, then shorter ones) > the app profile >
/// the global preference. `nil` on a profile means "inherit".
///
/// Storage: JSON `[AppProfile]` in the app's defaults suite
/// (`qalam.appProfiles.v1`, same plist as every other setting). App profiles
/// are written (configured ones plus the 50 most recently seen); site
/// profiles only once the user configures them — "recently seen" websites
/// live in memory for this session only, so no browsing history is written
/// to disk. Nothing here is ever logged except counts.
///
/// The legacy excluded-apps list (≤ 1.3.x) is migrated once into `off`
/// profiles; profiles are the only source of truth afterwards.
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    /// Persisted app + configured site profiles, plus this session's
    /// recently seen sites.
    private(set) var profiles: [AppProfile] = []
    /// Effective settings for the last focused external app / site. Read
    /// synchronously by the keystroke tap and the overlay (no AX). Profile
    /// edits and temporary pauses refresh it at once; global preferences are
    /// picked up on the next focus change or keystroke.
    private(set) var activeResolved: ResolvedProfile
    /// Last app other than QalamAI that was frontmost or typed in.
    private(set) var lastExternalApp: ExternalAppRef?
    /// Host of the page last typed in, while that app is a browser.
    private(set) var lastExternalHost: String?

    static let storageKey = "qalam.appProfiles.v1"
    static let migrationKey = "qalam.profilesMigrationV1"
    /// Bytes of an unreadable profile list, kept instead of being overwritten.
    private static let unreadableBackupKey = "qalam.appProfiles.v1.unreadable"

    static let maxUnconfiguredApps = 50
    static let maxRecentSites = 30
    /// `lastSeen` is refreshed (and written) at most this often per profile.
    static let lastSeenInterval: TimeInterval = 60
    static let globalInstructionsLimit = 500
    static let profileInstructionsLimit = 300

    @ObservationIgnored private let defaults: UserDefaults = QalamDefaults.suite
    @ObservationIgnored private var activeBundleID: String?
    @ObservationIgnored private var activeHost: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var savingDisabled = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    private init() {
        activeResolved = ResolvedProfile(
            bundleID: nil, host: nil, activation: .automatic, displayMode: .inline,
            tabAcceptEnabled: true, customInstructions: "", writingModeID: WritingMode.neutral.id,
            languagePreference: .auto, recordWriting: true, improveCompatibility: nil,
            autocorrectEnabled: true, temporarilyPausedUntil: nil)
        profiles = Self.load(from: defaults)
        activeResolved = resolve(bundleID: nil, host: nil)
    }

    // MARK: - Lifecycle

    /// Runs the one-time exclusions migration and starts following the
    /// frontmost app. Call after `UserPreferences.shared` is initialised and
    /// before the suggestion engine starts.
    func start() {
        guard !started else { return }
        started = true
        migrateExcludedAppsIfNeeded()
        pruneUnconfiguredApps()

        // Queue `.main` → delivered on the main thread.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let name = app?.localizedName
            let pid = app?.processIdentifier ?? 0
            MainActor.assumeIsolated {
                ProfileStore.shared.appDidActivate(bundleID: bundleID, name: name, pid: pid)
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            appDidActivate(bundleID: front.bundleIdentifier, name: front.localizedName,
                           pid: front.processIdentifier)
        }
        QLog.info(.profiles, "profiles loaded: \(configuredAppCount) app(s), \(configuredSiteCount) site(s) configured")
    }

    /// Writes a pending debounced save now (quit).
    func flushPendingSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveNow()
    }

    /// Drops a pending save and blocks later ones (uninstall: nothing may
    /// re-create the preferences file after it went to the Trash).
    func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        savingDisabled = true
    }

    // MARK: - Lookup

    func appProfile(bundleID: String) -> AppProfile? {
        let id = AppProfile.appID(bundleID)
        return profiles.first { $0.id == id }
    }

    func profile(id: String) -> AppProfile? {
        profiles.first { $0.id == id }
    }

    var configuredAppCount: Int {
        profiles.filter { $0.kind == .app && $0.isConfigured }.count
    }

    var configuredSiteCount: Int {
        profiles.filter { $0.kind == .domain && $0.isConfigured }.count
    }

    var didMigrateExclusions: Bool {
        defaults.bool(forKey: Self.migrationKey)
    }

    // MARK: - Editing

    @discardableResult
    func ensureApp(bundleID: String, name: String) -> AppProfile {
        if let existing = appProfile(bundleID: bundleID) { return existing }
        let p = AppProfile.newApp(bundleID: bundleID, name: name, lastSeen: Date())
        profiles.append(p)
        pruneUnconfiguredApps()
        scheduleSave()
        return p
    }

    @discardableResult
    func ensureDomain(host: String) -> AppProfile {
        let key = Self.normalizeHost(host) ?? host.lowercased()
        let id = AppProfile.domainID(key)
        if let existing = profiles.first(where: { $0.id == id }) { return existing }
        let p = AppProfile.newDomain(host: key, lastSeen: Date())
        profiles.append(p)
        pruneRecentSites()
        return p
    }

    /// Applies a user edit. `id`, `kind` and `key` can't change; an empty
    /// instruction string is stored as inherit. Persists (debounced 1 s).
    func update(id: String, _ mutate: (inout AppProfile) -> Void) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        let old = profiles[i]
        var p = old
        mutate(&p)
        p.id = old.id
        p.kind = old.kind
        p.key = old.key
        if p.customInstructions?.isEmpty == true { p.customInstructions = nil }
        guard p != old else { return }
        p.modifiedAt = Date()
        profiles[i] = p
        scheduleSave()
        refreshActiveResolved()
        // Only configured profiles are synced; resetting one back to inherit
        // reads as a deletion on the other Mac.
        if p.isConfigured {
            SyncHooks.changed(SyncKey.profile(p.id))
        } else if old.isConfigured {
            SyncHooks.deleted(SyncKey.profile(p.id))
        }
    }

    func delete(id: String) {
        let before = profiles.count
        let wasConfigured = profiles.first { $0.id == id }?.isConfigured ?? false
        profiles.removeAll { $0.id == id }
        guard profiles.count != before else { return }
        scheduleSave()
        refreshActiveResolved()
        if wasConfigured { SyncHooks.deleted(SyncKey.profile(id)) }
    }

    /// Writes app / site settings that came from another Mac. `lastSeen` is
    /// local bookkeeping and is never taken from the cloud copy; an app
    /// profile that was "deleted" elsewhere is reset to inherit here so the
    /// app stays in the recently-seen list.
    func applySyncItems(_ upserts: [AppProfile], deletions: [String]) {
        for id in deletions {
            guard let i = profiles.firstIndex(where: { $0.id == id }) else { continue }
            if profiles[i].kind == .app {
                var p = profiles[i]
                p.resetToInherit()
                p.modifiedAt = Date()
                profiles[i] = p
            } else {
                profiles.remove(at: i)
            }
        }
        for incoming in upserts {
            var p = incoming
            if let i = profiles.firstIndex(where: { $0.id == incoming.id }) {
                p.lastSeen = profiles[i].lastSeen
                profiles[i] = p
            } else {
                p.lastSeen = .distantPast
                profiles.append(p)
            }
        }
        pruneUnconfiguredApps()
        scheduleSave()
        refreshActiveResolved()
    }

    // MARK: - Resolution

    func resolve(bundleID: String?, host: String?) -> ResolvedProfile {
        let prefs = UserPreferences.shared
        let app = bundleID.flatMap { appProfile(bundleID: $0) }
        let sites = host.map { matchingDomainProfiles(for: $0) } ?? []
        // Most specific first.
        let chain: [AppProfile] = sites + (app.map { [$0] } ?? [])
        func first<T>(_ field: (AppProfile) -> T?) -> T? {
            for p in chain {
                if let value = field(p) { return value }
            }
            return nil
        }

        let activation: ResolvedActivation
        switch first({ $0.activation }) {
        case .alwaysOn?:  activation = .alwaysOn
        case .forceOnly?: activation = .forceOnly
        case .off?:       activation = .off
        case nil:         activation = .automatic
        }

        // A mode that was deleted since it was picked falls through.
        var writingModeID = prefs.activeModeID
        if chain.contains(where: { $0.writingModeId != nil }) {
            let known = Set(WritingModeStore.shared.allModes.map(\.id))
            if let id = first({ p in p.writingModeId.flatMap { known.contains($0) ? $0 : nil } }) {
                writingModeID = id
            }
        }

        var instructionParts = [String(prefs.customInstructions.prefix(Self.globalInstructionsLimit))]
        if let a = app?.customInstructions {
            instructionParts.append(String(a.prefix(Self.profileInstructionsLimit)))
        }
        if let s = sites.lazy.compactMap({ $0.customInstructions }).first(where: { !$0.isEmpty }) {
            instructionParts.append(String(s.prefix(Self.profileInstructionsLimit)))
        }
        let instructions = instructionParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return ResolvedProfile(
            bundleID: bundleID,
            host: host,
            activation: activation,
            displayMode: first({ $0.displayMode }) ?? .inline,
            tabAcceptEnabled: first({ $0.tabAcceptEnabled }) ?? true,
            customInstructions: instructions,
            writingModeID: writingModeID,
            languagePreference: first({ $0.languagePreference }) ?? .auto,
            recordWriting: first({ $0.recordWriting }) ?? !KnownApps.isTerminal(bundleID),
            improveCompatibility: app?.improveCompatibility,
            autocorrectEnabled: first({ $0.autocorrectEnabled }) ?? prefs.autoCorrectEnabled,
            temporarilyPausedUntil: TemporaryPauseStore.shared.until(bundleID: bundleID)
        )
    }

    /// Resolves the settings for a freshly read text context and does the
    /// "seen" bookkeeping. Runs on every context change, so observable state
    /// is only written when a value actually changes.
    @discardableResult
    func noteActive(_ context: TextContext) -> ResolvedProfile {
        guard let bundleID = context.appBundleID, bundleID != Constants.bundleID else {
            // No readable field, or QalamAI's own windows: not an external
            // app — keep the last one.
            return resolve(bundleID: context.appBundleID, host: nil)
        }
        let name = context.appName ?? bundleID
        let host = KnownApps.isBrowser(bundleID) ? context.host : nil
        let now = Date()
        noteSeen(app: bundleID, name: name, now: now)
        if let host { noteSeen(site: host, now: now) }

        let pid = context.pid != 0 ? context.pid
            : (lastExternalApp?.bundleID == bundleID ? (lastExternalApp?.pid ?? 0) : 0)
        let ref = ExternalAppRef(bundleID: bundleID, name: name, pid: pid)
        if lastExternalApp != ref { lastExternalApp = ref }
        if lastExternalHost != host { lastExternalHost = host }
        setActive(bundleID: bundleID, host: host)
        return activeResolved
    }

    /// Re-resolves `activeResolved` after a profile or pause change, and
    /// clears a suggestion the new settings no longer allow.
    func refreshActiveResolved() {
        setActive(bundleID: activeBundleID, host: activeHost)
        let r = activeResolved
        if r.activation == .off || r.activation == .forceOnly || r.isTemporarilyPaused,
           SuggestionEngine.shared.currentSuggestion != nil {
            SuggestionEngine.shared.dismiss()
        }
    }

    // MARK: - Hosts

    /// Lowercased host without scheme, credentials, port, path, trailing dot
    /// or leading "www.". nil when it isn't a plausible host name.
    nonisolated static func normalizeHost(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = s.range(of: "://") {
            s = String(s[scheme.upperBound...])
        }
        if let cut = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            s = String(s[..<cut])
        }
        if let at = s.lastIndex(of: "@") {
            s = String(s[s.index(after: at)...])
        }
        if let colon = s.lastIndex(of: ":") {
            let port = s[s.index(after: colon)...]
            if port.allSatisfy({ $0.isASCII && $0.isNumber }) {
                s = String(s[..<colon])
            }
        }
        while s.hasSuffix(".") { s.removeLast() }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        guard !s.isEmpty, s.count <= 253 else { return nil }
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        let valid = labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
        guard valid, labels.count >= 2 || s == "localhost" else { return nil }
        return s
    }

    /// `host` is `key` or one of its subdomains (label boundary).
    nonisolated static func host(_ host: String, matches key: String) -> Bool {
        host == key || host.hasSuffix("." + key)
    }

    // MARK: - Private

    private func matchingDomainProfiles(for host: String) -> [AppProfile] {
        profiles
            .filter { $0.kind == .domain && $0.isConfigured && Self.host(host, matches: $0.key) }
            .sorted { $0.key.count > $1.key.count }
    }

    private func setActive(bundleID: String?, host: String?) {
        activeBundleID = bundleID
        activeHost = host
        let r = resolve(bundleID: bundleID, host: host)
        if r != activeResolved { activeResolved = r }
    }

    private func appDidActivate(bundleID: String?, name: String?, pid: pid_t) {
        guard let bundleID, bundleID != Constants.bundleID else { return }
        let sameApp = lastExternalApp?.bundleID == bundleID && lastExternalApp?.pid == pid
        let ref = ExternalAppRef(bundleID: bundleID, name: name ?? bundleID, pid: pid)
        if lastExternalApp != ref { lastExternalApp = ref }
        let host = sameApp ? lastExternalHost : nil
        if lastExternalHost != host { lastExternalHost = host }
        setActive(bundleID: bundleID, host: host)
    }

    private func noteSeen(app bundleID: String, name: String, now: Date) {
        let id = AppProfile.appID(bundleID)
        if let i = profiles.firstIndex(where: { $0.id == id }) {
            guard now.timeIntervalSince(profiles[i].lastSeen) >= Self.lastSeenInterval else { return }
            profiles[i].lastSeen = now
            // Migrated exclusions of apps that weren't installed carry the
            // bundle id as their name until the app is seen.
            if profiles[i].displayName == bundleID, name != bundleID {
                profiles[i].displayName = name
            }
            scheduleSave()
        } else {
            profiles.append(.newApp(bundleID: bundleID, name: name, lastSeen: now))
            pruneUnconfiguredApps()
            scheduleSave()
        }
    }

    private func noteSeen(site host: String, now: Date) {
        let id = AppProfile.domainID(host)
        if let i = profiles.firstIndex(where: { $0.id == id }) {
            guard now.timeIntervalSince(profiles[i].lastSeen) >= Self.lastSeenInterval else { return }
            profiles[i].lastSeen = now
            if profiles[i].isConfigured { scheduleSave() }
        } else {
            // Memory only (never saved while unconfigured).
            profiles.append(.newDomain(host: host, lastSeen: now))
            pruneRecentSites()
        }
    }

    private func pruneUnconfiguredApps() {
        let unconfigured = profiles.filter { $0.kind == .app && !$0.isConfigured }
        guard unconfigured.count > Self.maxUnconfiguredApps else { return }
        let keep = Set(unconfigured.sorted { $0.lastSeen > $1.lastSeen }
            .prefix(Self.maxUnconfiguredApps).map(\.id))
        profiles.removeAll { $0.kind == .app && !$0.isConfigured && !keep.contains($0.id) }
    }

    private func pruneRecentSites() {
        let recent = profiles.filter { $0.kind == .domain && !$0.isConfigured }
        guard recent.count > Self.maxRecentSites else { return }
        let keep = Set(recent.sorted { $0.lastSeen > $1.lastSeen }
            .prefix(Self.maxRecentSites).map(\.id))
        profiles.removeAll { $0.kind == .domain && !$0.isConfigured && !keep.contains($0.id) }
    }

    private func migrateExcludedAppsIfNeeded() {
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        // The in-memory list is the right source: UserPreferences.init's
        // terminal revert filters it without persisting.
        let excluded = UserPreferences.shared.excludedBundleIDs
            .filter { !$0.isEmpty && $0 != Constants.bundleID }
        let now = Date()
        for bundleID in excluded {
            let id = AppProfile.appID(bundleID)
            if let i = profiles.firstIndex(where: { $0.id == id }) {
                profiles[i].activation = .off
                profiles[i].modifiedAt = now
            } else {
                var p = AppProfile.newApp(bundleID: bundleID,
                                          name: Self.appDisplayName(bundleID: bundleID) ?? bundleID,
                                          lastSeen: now)
                p.activation = .off
                p.modifiedAt = now
                profiles.append(p)
            }
        }
        // Profiles are written before the flag, so a failed write re-runs the
        // migration next launch instead of losing exclusions.
        if !excluded.isEmpty {
            saveTask?.cancel()
            guard saveNow() else { return }
        }
        defaults.set(true, forKey: Self.migrationKey)
        QLog.notice(.profiles, "migrated \(excluded.count) excluded app(s) to profiles")
    }

    /// Localized app name from the running app or its bundle on disk.
    static func appDisplayName(bundleID: String) -> String? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private func scheduleSave() {
        guard !savingDisabled else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    @discardableResult
    private func saveNow() -> Bool {
        saveTask = nil
        guard !savingDisabled else { return false }
        // Recently seen sites are never written.
        let persisted = profiles.filter { $0.kind == .app || $0.isConfigured }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            defaults.set(try encoder.encode(persisted), forKey: Self.storageKey)
            return true
        } catch {
            QLog.error(.profiles, "saving app profiles failed (\((error as NSError).code))")
            return false
        }
    }

    private static func load(from defaults: UserDefaults) -> [AppProfile] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([LossyAppProfile].self, from: data) else {
            // Keep the bytes aside instead of overwriting them on the next save.
            defaults.set(data, forKey: unreadableBackupKey)
            QLog.error(.profiles, "app profiles unreadable (\(data.count) bytes) — starting empty")
            return []
        }
        var seen = Set<String>()
        var result: [AppProfile] = []
        for p in list.compactMap(\.value) where seen.insert(p.id).inserted {
            if p.kind == .domain && !p.isConfigured { continue }
            result.append(p)
        }
        if result.count != list.count {
            QLog.notice(.profiles, "skipped \(list.count - result.count) unreadable or duplicate profile(s)")
        }
        return result
    }
}

/// One list element that may fail to decode without failing the list.
private struct LossyAppProfile: Decodable {
    let value: AppProfile?

    init(from decoder: Decoder) throws {
        value = try? AppProfile(from: decoder)
    }
}

/// "Pause in this app for 10 minutes" — memory only, gone on quit. Toggled
/// by the T4 shortcut / T5 field button; shown in the menu bar.
@MainActor
@Observable
final class TemporaryPauseStore {
    static let shared = TemporaryPauseStore()

    private(set) var pausedUntil: [String: Date] = [:]

    private init() {}

    /// Returns true when the app is now paused.
    @discardableResult
    func toggle(bundleID: String, minutes: Int = 10) -> Bool {
        if until(bundleID: bundleID) != nil {
            resume(bundleID: bundleID)
            return false
        }
        pause(bundleID: bundleID, minutes: minutes)
        return true
    }

    func pause(bundleID: String, minutes: Int) {
        var next = pausedUntil.filter { $0.value > Date() }
        next[bundleID] = Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        pausedUntil = next
        ProfileStore.shared.refreshActiveResolved()
    }

    func resume(bundleID: String) {
        pausedUntil = pausedUntil.filter { $0.key != bundleID && $0.value > Date() }
        ProfileStore.shared.refreshActiveResolved()
    }

    /// When the pause for this app ends, or nil. Doesn't mutate, so views
    /// can call it while rendering (expired entries are dropped on the next
    /// pause/resume).
    func until(bundleID: String?) -> Date? {
        guard let bundleID, let date = pausedUntil[bundleID], date > Date() else { return nil }
        return date
    }
}
