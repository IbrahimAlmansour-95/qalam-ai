import Foundation

enum OllamaInstallEvent: Sendable {
    case checking
    case downloading(fraction: Double, mb: Double)
    case extracting
    case installed(URL)
    case failed(String)
}

enum OllamaInstallSource: Sendable, Equatable {
    case bundled            // copy inside QalamAI.app/Contents/Helpers/Ollama.app
    case systemInstalled    // user already has Ollama on PATH or in /Applications
    case appSupport         // installed by us into ~/Library/Application Support/QalamAI
    case missing
}

/// Auto-installs Ollama so the user never has to download it themselves.
/// Priority:
///   1. Bundled inside the .app (build-time embedded)
///   2. System install (e.g. /Applications/Ollama.app or `which ollama`)
///   3. Previously-downloaded copy in ~/Library/Application Support/QalamAI
///   4. Download & extract on first launch
actor OllamaInstaller {
    static let shared = OllamaInstaller()

    private let downloadURL = URL(string: "https://github.com/ollama/ollama/releases/latest/download/Ollama-darwin.zip")!
    private var inFlight: Task<URL?, Never>?

    private init() {}

    // MARK: - Locations

    func bundledBinaryURL() -> URL? {
        // Embedded Ollama.app inside QalamAI.app/Contents/Helpers/Ollama.app
        guard let helpers = Bundle.main.url(forResource: "Helpers", withExtension: nil)
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers") as URL?
        else { return nil }
        let candidate = helpers
            .appendingPathComponent("Ollama.app/Contents/Resources/ollama")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    func systemBinaryURL() -> URL? {
        let candidates = [
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            (NSHomeDirectory() as NSString).appendingPathComponent(".ollama/bin/ollama"),
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func appSupportBinaryURL() -> URL? {
        guard let dir = appSupportInstallDir() else { return nil }
        let candidate = dir.appendingPathComponent("Ollama.app/Contents/Resources/ollama")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    func appSupportInstallDir() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent(Constants.appSupportDirName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func currentSource() -> OllamaInstallSource {
        if bundledBinaryURL() != nil { return .bundled }
        if systemBinaryURL() != nil { return .systemInstalled }
        if appSupportBinaryURL() != nil { return .appSupport }
        return .missing
    }

    /// Resolves to the binary URL for whichever source we are using.
    func resolveBinary() -> URL? {
        if let url = bundledBinaryURL() { return url }
        if let url = systemBinaryURL() { return url }
        if let url = appSupportBinaryURL() { return url }
        return nil
    }

    // MARK: - First-launch download

    /// Downloads Ollama-darwin.zip and extracts the inner Ollama.app into
    /// ~/Library/Application Support/QalamAI. Emits progress.
    func install() -> AsyncStream<OllamaInstallEvent> {
        AsyncStream { continuation in
            let work = Task {
                continuation.yield(.checking)
                if currentSource() != .missing {
                    if let url = resolveBinary() {
                        continuation.yield(.installed(url))
                    }
                    continuation.finish()
                    return
                }
                guard let installDir = appSupportInstallDir() else {
                    continuation.yield(.failed("Could not access Application Support"))
                    continuation.finish()
                    return
                }

                do {
                    let zipURL = installDir.appendingPathComponent("Ollama-darwin.zip")
                    try await download(to: zipURL, continuation: continuation)
                    continuation.yield(.extracting)
                    try unzip(zipURL: zipURL, into: installDir)
                    try? FileManager.default.removeItem(at: zipURL)

                    let binary = installDir
                        .appendingPathComponent("Ollama.app/Contents/Resources/ollama")
                    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
                        continuation.yield(.failed("Extracted archive is missing the ollama binary"))
                        continuation.finish()
                        return
                    }
                    continuation.yield(.installed(binary))
                } catch is CancellationError {
                    // ignore
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    // MARK: - Download

    private func download(to dest: URL,
                          continuation: AsyncStream<OllamaInstallEvent>.Continuation) async throws {
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: URLRequest(url: downloadURL))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "QalamAI.OllamaInstaller",
                          code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))"])
        }
        let total = max(1, response.expectedContentLength)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        var written: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var lastReport: Date = .now

        for try await byte in asyncBytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if Date().timeIntervalSince(lastReport) > 0.25 {
                    lastReport = .now
                    continuation.yield(.downloading(
                        fraction: Double(written) / Double(total),
                        mb: Double(written) / 1_048_576.0
                    ))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            continuation.yield(.downloading(
                fraction: Double(written) / Double(total),
                mb: Double(written) / 1_048_576.0
            ))
        }
    }

    // MARK: - Unzip

    private func unzip(zipURL: URL, into dest: URL) throws {
        // Remove a previous Ollama.app so re-installs don't merge stale files.
        let appPath = dest.appendingPathComponent("Ollama.app").path
        if FileManager.default.fileExists(atPath: appPath) {
            try FileManager.default.removeItem(atPath: appPath)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", "-o", zipURL.path, "-d", dest.path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw NSError(domain: "QalamAI.OllamaInstaller",
                          code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "unzip exited with status \(proc.terminationStatus)"])
        }
    }
}
