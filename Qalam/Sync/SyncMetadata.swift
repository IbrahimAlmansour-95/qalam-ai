import Foundation
import Observation

// MARK: - Local bookkeeping

/// When each synced item last changed on this Mac, plus tombstones for the
/// ones that were deleted. Nothing here is user content — only keys, dates
/// and device ids.
///
/// Items with no entry are treated as `.distantPast`, i.e. "has always been
/// here, never edited". That is what makes a Mac that turns sync on later
/// keep the copy already in iCloud instead of overwriting it with its own
/// untouched defaults.
@MainActor
@Observable
final class SyncMetadata {
    static let shared = SyncMetadata()

    /// Posted after any local change worth pushing.
    static let didChange = Notification.Name("com.qalamai.app.syncMetadataDidChange")

    struct Entry: Codable, Sendable, Equatable {
        var modifiedAt: Date
        var deviceID: String
        var deleted: Bool
    }

    nonisolated static let storageKey = "qalam.sync.meta.v1"
    nonisolated static let deviceIDKey = "qalam.sync.deviceID"
    /// A Mac that has been offline longer than this can resurrect an item
    /// that was deleted elsewhere (the usual last-writer-wins trade-off).
    nonisolated static let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60

    private(set) var entries: [String: Entry] = [:]
    /// True while remote winners are being written into the stores — their
    /// change hooks must not record a local edit, or every pull would look
    /// like something to push back.
    var isApplyingRemote = false

    @ObservationIgnored private let defaults: UserDefaults = QalamDefaults.suite
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var savingDisabled = false

    private init() {
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    /// This Mac's id inside the shared file. Created the first time sync is
    /// switched on and never changed afterwards.
    @discardableResult
    func ensureDeviceID() -> String {
        if let existing = Self.storedDeviceID { return existing }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.deviceIDKey)
        return id
    }

    /// The stored id, or a placeholder. Reading never creates one — the
    /// uninstaller uses `storedDeviceID` to tell whether this Mac ever
    /// synced.
    var deviceID: String { Self.storedDeviceID ?? "local" }

    nonisolated static var storedDeviceID: String? {
        QalamDefaults.suite.string(forKey: deviceIDKey)
    }

    func entry(_ key: String) -> Entry? { entries[key] }

    /// A local edit.
    func touch(_ key: String) {
        entries[key] = Entry(modifiedAt: Date(), deviceID: ensureDeviceID(), deleted: false)
        scheduleSave()
        notifyChanged()
    }

    /// A local deletion.
    func tombstone(_ key: String) {
        tombstone([key])
    }

    /// Batched so deleting a whole store is one observable change and one
    /// push, not thousands.
    func tombstone(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        let now = Date()
        let device = ensureDeviceID()
        var next = entries
        for key in keys {
            next[key] = Entry(modifiedAt: now, deviceID: device, deleted: true)
        }
        entries = next
        scheduleSave()
        notifyChanged()
    }

    /// Enable-time seeding: gives an item that was never edited a real date
    /// so it can reach a cloud copy that doesn't have it yet. Items that
    /// already carry a date keep it.
    func stampIfUnset(_ key: String, at date: Date) {
        guard entries[key] == nil else { return }
        entries[key] = Entry(modifiedAt: date, deviceID: ensureDeviceID(), deleted: false)
        scheduleSave()
    }

    /// Records the version we just took from the cloud, so the next gather
    /// reproduces exactly that item instead of pushing it back.
    func record(_ key: String, modifiedAt: Date, deviceID: String, deleted: Bool) {
        entries[key] = Entry(modifiedAt: modifiedAt, deviceID: deviceID, deleted: deleted)
        scheduleSave()
    }

    /// Drops tombstones nobody needs any more.
    func pruneTombstones(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.tombstoneLifetime)
        let before = entries.count
        entries = entries.filter { !($0.value.deleted && $0.value.modifiedAt < cutoff) }
        if entries.count != before { scheduleSave() }
    }

    /// Everything is forgotten (sync turned off with the cloud copy removed).
    func reset() {
        entries = [:]
        scheduleSave()
    }

    /// Writes a pending save now (quit).
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

    // MARK: - Private

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
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

    private func saveNow() {
        saveTask = nil
        guard !savingDisabled else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Store hooks

/// The one place the stores call when the user changes something. Every call
/// is a no-op unless sync is on, and while remote changes are being applied.
@MainActor
enum SyncHooks {
    static var isActive: Bool {
        UserPreferences.shared.syncEnabled && !SyncMetadata.shared.isApplyingRemote
    }

    /// Whether a DELETION is worth recording — a wider gate than `isActive`.
    ///
    /// Turning sync off does not remove the encrypted copy from iCloud Drive
    /// (the alert deliberately offers "Keep cloud copy", and the samples
    /// sub-toggle never removes anything at all). So an item deleted while
    /// sync is off is still in the remote payload, and without a local
    /// tombstone the next pull has nothing to beat it with: the merge treats
    /// it as a key we simply don't have, writes it back into the store and
    /// republishes it to every other Mac.
    ///
    /// The one Mac that has to stay out of this is one that never synced:
    /// `tombstone()` calls `ensureDeviceID()`, and minting that id is exactly
    /// what the uninstaller reads as "this Mac has iCloud data to look for".
    /// `everEnabled` is true only when the id already exists, so nothing here
    /// can create one.
    static var tombstonesActive: Bool {
        (UserPreferences.shared.syncEnabled || SyncManager.everEnabled)
            && !SyncMetadata.shared.isApplyingRemote
    }

    static func changed(_ key: String) {
        guard isActive else { return }
        SyncMetadata.shared.touch(key)
    }

    static func deleted(_ key: String) {
        guard tombstonesActive else { return }
        SyncMetadata.shared.tombstone(key)
    }

    /// A snippet's trigger is its key, so a rename is a delete plus an add.
    static func renamed(from oldKey: String, to newKey: String) {
        // Only the tombstone half outlives sync being off. Stamping a fresh
        // date on the new key must not: an untouched item is `.distantPast`
        // on purpose, so a Mac that was dormant for months loses to the cloud
        // copy instead of overwriting it.
        if oldKey != newKey, tombstonesActive { SyncMetadata.shared.tombstone(oldKey) }
        guard isActive else { return }
        SyncMetadata.shared.touch(newKey)
    }

    // MARK: Writing samples (separate file, separate opt-in)

    /// Samples are immutable and carry their own date, so a new one needs no
    /// metadata entry and no push of its own: the sample file is large, and
    /// rewriting it a few seconds after every recorded sample would keep
    /// iCloud Drive busy for no benefit. New samples ride the regular
    /// 15-minute cycle (or "Sync now"). Deletions do need a tombstone, and
    /// those push like any other change.
    ///
    /// A deletion is recorded even while sync or the samples opt-in is
    /// switched OFF — see `tombstonesActive`. Neither switch removes a sample
    /// file already in iCloud Drive, so without a tombstone the next samples
    /// cycle reads every deleted sample back out of the cloud copy and
    /// re-adds it. `sample:` keys never reach the settings bundle
    /// (`SyncKey.isSettings` excludes them), so the pending tombstones sit in
    /// local metadata until sample sync actually runs again.
    static func samplesDeleted(_ ids: [String]) {
        guard tombstonesActive, !ids.isEmpty else { return }
        SyncMetadata.shared.tombstone(ids.map { SyncKey.sample($0) })
    }
}
