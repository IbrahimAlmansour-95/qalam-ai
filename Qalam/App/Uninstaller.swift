import Foundation
import AppKit

/// Self-uninstall, with the choice to keep the user's downloaded models and
/// settings so a later reinstall is instant (no 50 GB re-download, no
/// re-entering preferences). Everything is moved to the Trash — never
/// permanently deleted — so it's recoverable.
@MainActor
enum Uninstaller {

    /// `~/Library/Application Support/QalamAI` — holds downloaded models and
    /// (when used) the auto-installed Ollama. This is the big one to preserve.
    static var appSupportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(Constants.appSupportDirName)
    }

    /// The preferences plist holding all settings.
    static var prefsPlist: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Preferences/\(Constants.bundleID).plist")
    }

    /// `~/Library/Logs/QalamAI` — the rotating log and local crash/hang
    /// diagnostics. No value once the app is gone, so trashed in both modes.
    static var logsDir: URL? {
        QLog.logDirectory
    }

    /// `<iCloud Drive>/QalamAI` — the encrypted sync copy. nil unless this
    /// Mac ever enabled sync and the folder is actually there.
    static var syncCloudFolder: URL? {
        guard SyncManager.everEnabled else { return nil }
        let folder = SyncManager.cloudFolder
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    /// Regenerable system caches for the app.
    static var cacheDirs: [URL] {
        guard let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return [] }
        return [
            lib.appendingPathComponent("Caches/\(Constants.bundleID)"),
            lib.appendingPathComponent("HTTPStorages/\(Constants.bundleID)"),
        ]
    }

    /// Human-readable size of the kept-or-removed data (mostly the models).
    static func dataFootprint() -> String {
        guard let dir = appSupportDir,
              let size = directorySize(dir), size > 0 else { return "0 MB" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    static func revealDataInFinder() {
        guard let dir = appSupportDir else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    /// Uninstall. `keepData == true` removes only the app bundle and logs
    /// (models + settings survive for a future reinstall). `false` also
    /// trashes the models, settings, and caches. Quits the app afterward.
    static func uninstall(keepData: Bool) {
        // Sync timers stop first, so a push in flight can't re-create what
        // we are about to trash.
        SyncManager.shared.stopActivity()
        // A debounced profile or sync-metadata save landing after the prefs
        // plist went to the Trash would re-create it. Keeping data: write it
        // now instead.
        if keepData {
            ProfileStore.shared.flushPendingSave()
            SyncMetadata.shared.flushPendingSave()
            PersonalizationStore.flushPendingSaveBlocking()
        } else {
            ProfileStore.shared.cancelPendingSave()
            SyncMetadata.shared.cancelPendingSave()
            // The sample store's debounced save re-creates its own 0700
            // directory, so a write landing after the trash loop below would
            // restore the encrypted writing store — with its keychain key
            // already deleted, i.e. unopenable and unexplainable. Raised
            // synchronously here, before anything is trashed.
            PersonalizationStore.disableWrites()
        }
        var toTrash: [URL] = [Bundle.main.bundleURL]
        if let logs = logsDir { toTrash.append(logs) }

        if !keepData {
            if let s = appSupportDir { toTrash.append(s) }
            if let p = prefsPlist { toTrash.append(p) }
            toTrash.append(contentsOf: cacheDirs)
            // The encrypted writing store lives inside App Support (trashed
            // above); its key is a keychain item, which has to go too.
            // Synchronous on main is fine here — the app quits in 0.4 s.
            KeychainHelper.delete(service: PersonalizationStore.keychainService,
                                  account: PersonalizationStore.keychainAccount)
            // Same for the sync passphrase (its 0600 fallback sits in App
            // Support). The encrypted copy in iCloud Drive is a data
            // location of ours too, so it goes to the Trash as well — but
            // only if this Mac ever turned sync on, so we never touch
            // Mobile Documents otherwise. Other Macs keep their own copies
            // and re-create it on their next push.
            KeychainHelper.delete(service: SyncManager.keychainService,
                                  account: SyncManager.keychainAccount)
            if let cloud = syncCloudFolder { toTrash.append(cloud) }
        }

        // Stop the bundled engine + any taps before we go. The flag goes up
        // first so the engine's exit can never schedule an auto-restart.
        OllamaService.shutdownFlag.set()
        Task { await OllamaService.shared.stopServer() }
        KeystrokeInterceptor.shared.uninstall()
        QLog.notice(.app, "uninstalling (keep data: \(keepData))")
        // No log line may re-create the folder after it is trashed.
        QLog.disableFileLogging()
        DiagnosticsCollector.shared.stop()

        // Move everything that exists to the Trash (reversible).
        let fm = FileManager.default
        for url in toTrash where fm.fileExists(atPath: url.path) {
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }

        // Give the trash operation a beat, then quit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Helpers

    private static func directorySize(_ url: URL) -> Int64? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url,
                                     includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                                     options: [],
                                     errorHandler: nil) else { return nil }
        var total: Int64 = 0
        for case let fileURL as URL in en {
            let vals = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(vals?.totalFileAllocatedSize ?? vals?.fileAllocatedSize ?? 0)
        }
        return total
    }
}
