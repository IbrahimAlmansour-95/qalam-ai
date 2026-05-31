import Foundation

struct InstalledModel: Sendable, Hashable {
    let name: String
    let sizeBytes: Int64
    let modifiedAt: Date
}

enum ModelDownloadEvent: Sendable {
    case started
    case progress(fraction: Double, statusText: String)
    case completed
    case failed(String)
    case cancelled
}

enum OllamaState: Sendable, Equatable {
    case unknown
    case notInstalled
    case stopped
    case starting
    case running
}

actor OllamaService {
    static let shared = OllamaService()

    private let session: URLSession
    private(set) var state: OllamaState = .unknown
    private(set) var installedModels: [InstalledModel] = []
    private var stateContinuations: [UUID: AsyncStream<OllamaState>.Continuation] = [:]
    private var installedModelContinuations: [UUID: AsyncStream<[InstalledModel]>.Continuation] = [:]
    private var serveProcess: Process?
    private var downloadProcesses: [String: Process] = [:]

    private init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Subscriptions

    func stateStream() -> AsyncStream<OllamaState> {
        AsyncStream { continuation in
            let id = UUID()
            stateContinuations[id] = continuation
            continuation.yield(state)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStateContinuation(id) }
            }
        }
    }

    func installedModelsStream() -> AsyncStream<[InstalledModel]> {
        AsyncStream { continuation in
            let id = UUID()
            installedModelContinuations[id] = continuation
            continuation.yield(installedModels)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeInstalledModelsContinuation(id) }
            }
        }
    }

    private func removeStateContinuation(_ id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }
    private func removeInstalledModelsContinuation(_ id: UUID) {
        installedModelContinuations.removeValue(forKey: id)
    }

    private func setState(_ newState: OllamaState) {
        guard newState != state else { return }
        state = newState
        for c in stateContinuations.values { c.yield(newState) }
    }

    private func setInstalledModels(_ list: [InstalledModel]) {
        installedModels = list
        for c in installedModelContinuations.values { c.yield(list) }
    }

    // MARK: - Detection / lifecycle

    /// Resolves the `ollama` binary. Priority: bundled → system install →
    /// app-support install. Returns nil if none is available yet (the caller
    /// should kick off `OllamaInstaller.install()`).
    func locateBinary() async -> URL? {
        await OllamaInstaller.shared.resolveBinary()
    }

    /// Probe the local Ollama daemon. Updates `state`.
    func probe() async {
        let pingURL = Constants.Ollama.tagsURL
        var req = URLRequest(url: pingURL)
        req.timeoutInterval = 1.5

        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                setState(.running)
                parseTagsResponse(data: data)
                return
            }
        } catch {
            // not reachable
        }
        if await locateBinary() != nil {
            setState(.stopped)
        } else {
            setState(.notInstalled)
        }
    }

    private(set) var lastServeError: String?

    /// Launch `ollama serve` in the background. Captures stderr so failures
    /// don't disappear into the void.
    /// Kill any processes from OUR bundled Ollama (serve + runner children),
    /// matched by the bundle helper path so a system Ollama is never touched.
    /// Synchronous + nonisolated so it can run from `applicationWillTerminate`.
    nonisolated static func killBundledEngine() {
        let helperPath = Bundle.main.bundlePath + "/Contents/Helpers/Ollama"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", helperPath]
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            NSLog("QalamAI: killBundledEngine pkill failed: %@", error.localizedDescription)
        }
    }

    func startServer() async {
        // Self-heal: if we aren't tracking a serve process, any bundled Ollama
        // still running is an orphan from a prior unclean exit — clear it so we
        // don't accumulate model-loaded runners that thrash memory. (A SYSTEM
        // Ollama lives at a different path and is left alone, then reused below.)
        if serveProcess == nil {
            Self.killBundledEngine()
        }
        // Re-probe first — if someone else already runs Ollama (or our last
        // serve is still alive), we don't need to spawn another.
        await probe()
        if state == .running { return }

        guard let binary = await locateBinary() else {
            setState(.notInstalled)
            return
        }
        setState(.starting)

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["serve"]

        // Use our app-support dir as the model cache so a bundled-Ollama
        // install doesn't fight any system Ollama for ~/.ollama/models.
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = "127.0.0.1:11434"
        if let dir = await OllamaInstaller.shared.appSupportInstallDir() {
            let modelsDir = dir.appendingPathComponent("models")
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            env["OLLAMA_MODELS"] = modelsDir.path
        }
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        // Drain stderr — keep the last few KB in `lastServeError` for diagnosis.
        // Wrapped in a Sendable class because the pipe handler runs on a
        // background thread.
        let buffer = StderrBuffer()
        let errHandler: @Sendable (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let s = String(data: data, encoding: .utf8) else { return }
            buffer.append(s)
            NSLog("QalamAI: ollama serve stderr: %@", s)
        }
        errPipe.fileHandleForReading.readabilityHandler = errHandler
        outPipe.fileHandleForReading.readabilityHandler = errHandler

        proc.terminationHandler = { @Sendable [weak self] p in
            let snapshot = buffer.value
            NSLog("QalamAI: ollama serve exited (status=%d)", p.terminationStatus)
            Task { [weak self] in
                await self?.serverDidExit(status: Int(p.terminationStatus), stderr: snapshot)
            }
        }

        do {
            try proc.run()
            serveProcess = proc
            NSLog("QalamAI: launched ollama serve from %@", binary.path)
        } catch {
            lastServeError = "Failed to launch engine: \(error.localizedDescription)"
            NSLog("QalamAI: launch failed — %@", error.localizedDescription)
            setState(.stopped)
            return
        }

        // Poll until ready or timeout (~15s).
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await probe()
            if state == .running { return }
        }
        // Didn't come up. Capture whatever the daemon printed.
        if state != .running {
            let drained = buffer.value
            lastServeError = drained.isEmpty
                ? "Engine did not start within 15s."
                : drained
            NSLog("QalamAI: ollama did not come up. Last stderr: %@", drained)
        }
    }

    /// Thread-safe append-only buffer used by the stderr drain handler.
    final class StderrBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: String = ""

        func append(_ s: String) {
            lock.lock(); defer { lock.unlock() }
            storage.append(s)
            if storage.count > 4000 {
                storage = String(storage.suffix(4000))
            }
        }

        var value: String {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
    }

    private func serverDidExit(status: Int, stderr: String) {
        serveProcess = nil
        if status != 0 {
            lastServeError = stderr.isEmpty ? "Engine exited with status \(status)" : stderr
        }
        setState(.stopped)
    }

    /// Terminate the bundled `ollama serve` process we launched (used on
    /// uninstall / quit). No-op if we didn't start one.
    func stopServer() {
        serveProcess?.terminate()
        serveProcess = nil
        // SIGTERM to `ollama serve` doesn't always reap its runner children;
        // pkill the whole bundled set by path as a backstop.
        Self.killBundledEngine()
        setState(.stopped)
    }

    /// Periodic health check (every 10s).
    func startHealthChecks() {
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.probe()
                try? await Task.sleep(nanoseconds: UInt64(Constants.Ollama.healthCheckInterval * 1_000_000_000))
            }
        }
    }

    // MARK: - Installed models

    @discardableResult
    func refreshInstalledModels() async -> [InstalledModel] {
        var req = URLRequest(url: Constants.Ollama.tagsURL)
        req.timeoutInterval = 3
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return installedModels
            }
            parseTagsResponse(data: data)
        } catch {
            // ignore; keep previous list
        }
        return installedModels
    }

    private func parseTagsResponse(data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]]
        else { return }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        let parsed: [InstalledModel] = models.compactMap { m in
            guard let name = m["name"] as? String else { return nil }
            let size = (m["size"] as? Int64) ?? Int64((m["size"] as? Int) ?? 0)
            var modified = Date()
            if let s = m["modified_at"] as? String {
                modified = iso.date(from: s) ?? fallback.date(from: s) ?? Date()
            }
            return InstalledModel(name: name, sizeBytes: size, modifiedAt: modified)
        }
        setInstalledModels(parsed)
    }

    func isInstalled(_ tag: String) -> Bool {
        installedModels.contains { $0.name == tag || $0.name == tag + ":latest" }
    }

    // MARK: - Download

    func download(tag: String) -> AsyncStream<ModelDownloadEvent> {
        AsyncStream { continuation in
            let starter = Task { [weak self] in
                guard let self else { return }
                guard let binary = await self.locateBinary() else {
                    continuation.yield(.failed("Engine is not available. Reopen the app to retry installation."))
                    continuation.finish()
                    return
                }

                // Make sure the daemon is up. If startServer was never called or
                // the server has crashed, kick it off now and wait for it.
                if await self.state != .running {
                    continuation.yield(.progress(fraction: 0, statusText: "Starting engine…"))
                    await self.startServer()
                }
                if await self.state != .running {
                    let detail = await self.lastServeError ?? "Engine did not start"
                    continuation.yield(.failed("Engine unavailable. \(detail)"))
                    continuation.finish()
                    return
                }

                await self.beginDownload(tag: tag, binary: binary, continuation: continuation)
            }
            continuation.onTermination = { _ in starter.cancel() }
        }
    }

    private func beginDownload(tag: String,
                               binary: URL,
                               continuation: AsyncStream<ModelDownloadEvent>.Continuation) {
        if downloadProcesses[tag] != nil {
            continuation.yield(.failed("Download already in progress"))
            continuation.finish()
            return
        }
        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["pull", tag]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        downloadProcesses[tag] = proc
        continuation.yield(.started)

        let handler: @Sendable (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            for raw in lines {
                let line = String(raw).trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                if let event = OllamaService.parseProgressLine(line) {
                    continuation.yield(event)
                }
            }
        }
        outPipe.fileHandleForReading.readabilityHandler = handler
        errPipe.fileHandleForReading.readabilityHandler = handler

        proc.terminationHandler = { @Sendable p in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            if p.terminationReason == .uncaughtSignal {
                continuation.yield(.cancelled)
            } else if p.terminationStatus == 0 {
                continuation.yield(.completed)
            } else {
                continuation.yield(.failed("Exit \(p.terminationStatus)"))
            }
            continuation.finish()
            Task { [weak self] in await self?.clearDownload(tag: tag) }
        }

        do {
            try proc.run()
        } catch {
            continuation.yield(.failed(error.localizedDescription))
            continuation.finish()
            Task { [weak self] in await self?.clearDownload(tag: tag) }
        }
    }

    func cancelDownload(tag: String) {
        guard let proc = downloadProcesses[tag] else { return }
        proc.terminate()
    }

    private func clearDownload(tag: String) {
        downloadProcesses.removeValue(forKey: tag)
        Task { await refreshInstalledModels() }
    }

    /// Parses one progress line from `ollama pull` output.
    static func parseProgressLine(_ line: String) -> ModelDownloadEvent? {
        // Examples:
        //   pulling manifest
        //   pulling 0c0acd5b9a6e: 100% ▕████████████▏ 1.6 GB
        //   pulling 0c0acd5b9a6e:  37% ▕████        ▏ 600 MB/1.6 GB
        //   verifying sha256 digest
        //   writing manifest
        //   success
        if line.contains("success") {
            return .completed
        }
        // Look for percentage.
        if let pctRange = line.range(of: #"(\d+)%"#, options: .regularExpression) {
            let pctStr = String(line[pctRange]).replacingOccurrences(of: "%", with: "")
            if let pct = Double(pctStr) {
                return .progress(fraction: pct / 100.0, statusText: line)
            }
        }
        // Generic status lines (indeterminate).
        return .progress(fraction: 0, statusText: line)
    }

    // MARK: - Delete

    func deleteModel(tag: String) async throws {
        var req = URLRequest(url: Constants.Ollama.deleteURL)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": tag])

        let (_, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(
                domain: "Qalam.Ollama",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Delete failed: HTTP \(http.statusCode)"]
            )
        }
        await refreshInstalledModels()
    }
}
