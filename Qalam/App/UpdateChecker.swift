import Foundation
import Observation
import AppKit

/// Lightweight GitHub-releases update checker. Polls the public releases API,
/// compares the latest tag against the running bundle version, and exposes an
/// `available` release for the UI to surface. No Sparkle dependency — fits the
/// manual swiftc build and the un-sandboxed app.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    struct Release: Sendable, Equatable {
        let version: String      // normalized, e.g. "1.0.1"
        let htmlURL: URL         // release page
        let dmgURL: URL?         // first .dmg asset, if any
    }

    enum CheckState: Equatable { case idle, checking, upToDate, found }
    private(set) var available: Release?
    private(set) var checkState: CheckState = .idle

    /// In-app download/install of the new DMG.
    enum InstallState: Equatable {
        case idle
        case downloading(Double)   // 0…1
        case mounting
        case ready                 // DMG opened for drag-install
        case failed(String)
    }
    private(set) var installState: InstallState = .idle
    private var timer: Timer?

    /// `owner/repo` for the public releases API.
    private let repo = "IbrahimAlmansour-95/qalam-ai"

    private init() {}

    func start() {
        guard UserPreferences.shared.autoUpdateEnabled else { return }
        Task { await checkNow() }
        // Re-check once a day while running.
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkNow() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func checkNow() async {
        guard let latest = await fetchLatest() else { return }
        if isNewer(latest.version, than: Constants.version) {
            available = latest
        } else {
            available = nil
        }
    }

    /// User-triggered check from Settings; updates `checkState` for the UI even
    /// when auto-update is off.
    func checkManually() async {
        checkState = .checking
        guard let latest = await fetchLatest() else { checkState = .idle; return }
        if isNewer(latest.version, than: Constants.version) {
            available = latest
            checkState = .found
        } else {
            available = nil
            checkState = .upToDate
        }
    }

    func openDownload() {
        guard let release = available else { return }
        NSWorkspace.shared.open(release.dmgURL ?? release.htmlURL)
    }

    // MARK: - In-app download & install

    /// Download the new DMG with progress, then open (mount) it so the user can
    /// drag QalamAI to Applications. We can't silently swap the bundle without
    /// a Developer ID signature, so the standard drag-install flow is the safe,
    /// honest path — but the download happens inside the app with a progress bar
    /// instead of bouncing to a browser.
    func downloadAndInstall() async {
        guard let release = available, let dmgURL = release.dmgURL else {
            // No direct asset — fall back to the release page.
            openDownload()
            return
        }
        installState = .downloading(0)
        do {
            let dest = try await download(dmgURL, version: release.version)
            installState = .mounting
            // Reveal + open the DMG; macOS mounts it and shows the drag window.
            NSWorkspace.shared.activateFileViewerSelecting([dest])
            NSWorkspace.shared.open(dest)
            installState = .ready
        } catch {
            installState = .failed(error.localizedDescription)
        }
    }

    func resetInstallState() { installState = .idle }

    private func download(_ url: URL, version: String) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let total = response.expectedContentLength
        let dir = updatesDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("QalamAI-\(version)-arm64.dmg")
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var lastReported = 0.0
        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= (1 << 16) {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            if total > 0 {
                let frac = Double(received) / Double(total)
                if frac - lastReported >= 0.01 {
                    lastReported = frac
                    installState = .downloading(frac)
                }
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
        return dest
    }

    private func updatesDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent(Constants.appSupportDirName, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    // MARK: - Networking

    private func fetchLatest() async -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }

            let tag = (obj["tag_name"] as? String) ?? (obj["name"] as? String) ?? ""
            let htmlString = (obj["html_url"] as? String) ?? "https://github.com/\(repo)/releases"
            guard let htmlURL = URL(string: htmlString) else { return nil }

            var dmgURL: URL?
            if let assets = obj["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                       let dl = asset["browser_download_url"] as? String,
                       let u = URL(string: dl) {
                        dmgURL = u
                        break
                    }
                }
            }
            return Release(version: normalize(tag), htmlURL: htmlURL, dmgURL: dmgURL)
        } catch {
            return nil
        }
    }

    // MARK: - Version comparison

    /// Strips a leading "v" and anything after the numeric core.
    private func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Semantic-ish comparison of dotted numeric versions.
    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
