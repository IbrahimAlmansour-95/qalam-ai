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

/// Auto-restart supervision of the bundled `ollama serve` we launched.
enum EngineSupervisorState: Sendable, Equatable {
    /// Nothing to do (engine up, never crashed, or not ours to supervise).
    case idle
    /// The engine exited unexpectedly; restart `attempt` is scheduled/running.
    case restarting(attempt: Int)
    /// Too many unexpected exits in a short window — gave up until the user
    /// retries.
    case failed
}

actor OllamaService {
    static let shared = OllamaService()

    private let session: URLSession
    private(set) var state: OllamaState = .unknown
    private(set) var installedModels: [InstalledModel] = []
    private var stateContinuations: [UUID: AsyncStream<OllamaState>.Continuation] = [:]
    private var installedModelContinuations: [UUID: AsyncStream<[InstalledModel]>.Continuation] = [:]
    private var serveProcess: Process?
    /// Identity of `serveProcess`, captured by its termination handler so an
    /// exit can be matched to the process we're tracking (a monotonically
    /// increasing token — never reused, unlike an object address).
    private var serveProcessToken: Int?
    private var nextServeProcessToken = 0
    private var downloadProcesses: [String: Process] = [:]

    // Engine supervision (auto-restart after an unexpected exit).
    private(set) var supervisorState: EngineSupervisorState = .idle
    private var supervisorContinuations: [UUID: AsyncStream<EngineSupervisorState>.Continuation] = [:]
    /// Unexpected exits inside the rolling window.
    private var crashTimes: [Date] = []
    private var startInFlight: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    /// Exits counted within this window…
    private static let crashWindow: TimeInterval = 300
    /// …before giving up (the 5th exit in 5 minutes → `.failed`).
    private static let maxCrashesInWindow = 5
    /// Longest wait between restart attempts.
    private static let maxRestartDelay: TimeInterval = 30

    /// Set once the app is quitting or uninstalling: engine exits from then on
    /// are intentional and must never trigger a restart. Synchronous and
    /// nonisolated so `applicationWillTerminate` can set it.
    final class ShutdownFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            lock.lock(); defer { lock.unlock() }
            value = true
        }

        var isSet: Bool {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }
    static let shutdownFlag = ShutdownFlag()

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

    func supervisorStream() -> AsyncStream<EngineSupervisorState> {
        AsyncStream { continuation in
            let id = UUID()
            supervisorContinuations[id] = continuation
            continuation.yield(supervisorState)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSupervisorContinuation(id) }
            }
        }
    }

    private func removeStateContinuation(_ id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }
    private func removeSupervisorContinuation(_ id: UUID) {
        supervisorContinuations.removeValue(forKey: id)
    }
    private func removeInstalledModelsContinuation(_ id: UUID) {
        installedModelContinuations.removeValue(forKey: id)
    }

    private func setState(_ newState: OllamaState) {
        guard newState != state else { return }
        state = newState
        for c in stateContinuations.values { c.yield(newState) }
    }

    private func setSupervisor(_ newState: EngineSupervisorState) {
        guard newState != supervisorState else { return }
        supervisorState = newState
        for c in supervisorContinuations.values { c.yield(newState) }
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
            QLog.error(.engine, "killBundledEngine pkill failed (\((error as NSError).domain) \((error as NSError).code))")
        }
    }

    /// Re-entrancy safe: concurrent callers (launch, installer, download,
    /// auto-restart) share one in-flight start instead of spawning two
    /// `ollama serve` processes that fight over the port.
    func startServer() async {
        if let inFlight = startInFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.performStartServer() }
        startInFlight = task
        await task.value
        startInFlight = nil
        // Our engine is up (or a system Ollama answered): any pending
        // crash-restart or earlier give-up is moot. The crash history is kept,
        // so a crash loop still stops quickly.
        if state == .running {
            restartTask?.cancel()
            restartTask = nil
            setSupervisor(.idle)
        }
    }

    private func performStartServer() async {
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
        // Quitting / uninstalling while this start was queued — don't spawn.
        guard !Self.shutdownFlag.isSet else { return }
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
            // Never the chunk itself: the engine can echo request data.
            QLog.debug(.engine, "stderr chunk (\(s.count) chars)")
        }
        errPipe.fileHandleForReading.readabilityHandler = errHandler
        outPipe.fileHandleForReading.readabilityHandler = errHandler

        nextServeProcessToken += 1
        let token = nextServeProcessToken
        proc.terminationHandler = { @Sendable [weak self] p in
            let snapshot = buffer.value
            QLog.info(.engine, "ollama serve exited (status=\(p.terminationStatus))")
            Task { [weak self] in
                await self?.serverDidExit(token: token, status: Int(p.terminationStatus), stderr: snapshot)
            }
        }

        do {
            try proc.run()
            serveProcess = proc
            serveProcessToken = token
            // Source kind only — never the path.
            let source = binary.path.hasPrefix(Bundle.main.bundlePath) ? "bundled"
                : binary.path.contains("/Application Support/") ? "app support" : "system"
            QLog.info(.engine, "launched ollama serve (\(source))")
        } catch {
            lastServeError = "Failed to launch engine: \(error.localizedDescription)"
            QLog.error(.engine, "ollama serve launch failed (\((error as NSError).domain) \((error as NSError).code))")
            setState(.stopped)
            return
        }

        // Poll until ready or timeout (~15s).
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            // The process we just launched already exited (or was stopped) —
            // its exit handler owns what happens next; stop waiting for it.
            guard serveProcessToken == token else { return }
            await probe()
            if state == .running { return }
        }
        // Didn't come up. Capture whatever the daemon printed.
        if state != .running {
            let drained = buffer.value
            lastServeError = drained.isEmpty
                ? "Engine did not start within 15s."
                : drained
            QLog.error(.engine, "engine did not come up (stderr \(drained.count) chars)")
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

    private func serverDidExit(token: Int, status: Int, stderr: String) {
        // Only the process we're tracking counts. `stopServer()` clears the
        // token BEFORE terminating, so an intentional stop lands here as
        // untracked and is ignored.
        guard serveProcessToken == token else { return }
        serveProcess = nil
        serveProcessToken = nil
        if status != 0 {
            lastServeError = stderr.isEmpty ? "Engine exited with status \(status)" : stderr
        }
        setState(.stopped)
        // Quit / uninstall in progress: the exit is expected.
        guard !Self.shutdownFlag.isSet else { return }
        recordUnexpectedExit()
    }

    /// Counts an unexpected engine exit and schedules a restart with
    /// exponential backoff (1, 2, 4, 8 s … capped at 30 s). The 5th exit
    /// within 5 minutes gives up and surfaces `.failed`.
    private func recordUnexpectedExit() {
        let now = Date()
        crashTimes = crashTimes.filter { now.timeIntervalSince($0) < Self.crashWindow } + [now]
        restartTask?.cancel()
        restartTask = nil
        if crashTimes.count >= Self.maxCrashesInWindow {
            setSupervisor(.failed)
            QLog.error(.engine, "engine exited \(crashTimes.count) times in 5 min — auto-restart stopped")
            return
        }
        let attempt = crashTimes.count
        let delay = min(Self.maxRestartDelay, pow(2, Double(attempt - 1)))
        setSupervisor(.restarting(attempt: attempt))
        QLog.notice(.engine, "engine exited unexpectedly — restart attempt \(attempt) in \(Int(delay))s")
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.restartAfterCrash()
        }
    }

    private func restartAfterCrash() async {
        restartTask = nil
        guard !Self.shutdownFlag.isSet else { return }
        // Someone else (download, installer, retry) already brought it back.
        guard serveProcess == nil else {
            setSupervisor(.idle)
            return
        }
        await startServer()
        guard !Self.shutdownFlag.isSet else { return }
        if state == .running || serveProcess != nil {
            // Up — or launched and still alive (its exit, if any, is
            // supervised again). ModelManager re-warms the active model on the
            // transition into `.running`.
            if case .restarting = supervisorState { setSupervisor(.idle) }
        } else if restartTask == nil, supervisorState != .failed {
            // Never launched (binary missing, spawn error) and no exit event
            // will come — count it so we still back off and eventually stop.
            recordUnexpectedExit()
        }
    }

    /// "Retry" from the UI after `.failed`: clear the crash history and start
    /// the engine again.
    func retryAfterFailure() async {
        guard !Self.shutdownFlag.isSet else { return }
        restartTask?.cancel()
        restartTask = nil
        crashTimes = []
        setSupervisor(.idle)
        await startServer()
    }

    /// Terminate the bundled `ollama serve` process we launched (used on
    /// uninstall / quit). No-op if we didn't start one. Intentional: never
    /// triggers an auto-restart.
    func stopServer() {
        restartTask?.cancel()
        restartTask = nil
        // Untrack BEFORE terminating so the exit handler ignores this exit.
        let proc = serveProcess
        serveProcess = nil
        serveProcessToken = nil
        proc?.terminate()
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
