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

    /// Uninstall. `keepData == true` removes only the app bundle (models +
    /// settings survive for a future reinstall). `false` also trashes the
    /// models, settings, and caches. Quits the app afterward.
    static func uninstall(keepData: Bool) {
        var toTrash: [URL] = [Bundle.main.bundleURL]

        if !keepData {
            if let s = appSupportDir { toTrash.append(s) }
            if let p = prefsPlist { toTrash.append(p) }
            toTrash.append(contentsOf: cacheDirs)
        }

        // Stop the bundled engine + any taps before we go.
        Task { await OllamaService.shared.stopServer() }
        KeystrokeInterceptor.shared.uninstall()

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
