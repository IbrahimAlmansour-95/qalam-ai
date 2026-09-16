import Foundation
import Observation

@MainActor
@Observable
final class ModelManager {
    static let shared = ModelManager()

    private(set) var installedTags: Set<String> = []
    private(set) var ollamaState: OllamaState = .unknown
    private(set) var ollamaSource: OllamaInstallSource = .missing
    private(set) var installerProgress: Double = 0
    private(set) var installerMB: Double = 0
    private(set) var installerStatus: String = ""
    private(set) var installerActive: Bool = false
    private(set) var activeDownloads: [String: Double] = [:]   // tag → fraction
    private(set) var downloadStatusText: [String: String] = [:]
    private(set) var lastError: String?
    /// Auto-restart state of the bundled engine (menu bar status / Retry).
    private(set) var engineSupervisor: EngineSupervisorState = .idle

    var detectedRAMGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }

    private init() {}

    func start() {
        Task {
            ollamaSource = await OllamaInstaller.shared.currentSource()
            await ensureOllamaAvailable()
            await OllamaService.shared.probe()
            _ = await OllamaService.shared.refreshInstalledModels()
            await observeOllamaState()
        }
        Task {
            await observeInstalledModels()
        }
        Task {
            await OllamaService.shared.startHealthChecks()
        }
        Task {
            for await s in await OllamaService.shared.supervisorStream() {
                engineSupervisor = s
            }
        }
    }

    /// Runs the auto-installer if Ollama isn't found anywhere yet. Updates
    /// installer* fields so the UI can render progress.
    func ensureOllamaAvailable() async {
        ollamaSource = await OllamaInstaller.shared.currentSource()
        guard ollamaSource == .missing else { return }
        installerActive = true
        installerStatus = "Preparing engine…"
        for await event in await OllamaInstaller.shared.install() {
            switch event {
            case .checking:
                installerStatus = "Checking for engine…"
            case .downloading(let fraction, let mb):
                installerProgress = fraction
                installerMB = mb
                installerStatus = String(format: "Downloading engine… %.1f MB", mb)
            case .extracting:
                installerStatus = "Installing engine…"
            case .installed:
                installerStatus = "Engine ready."
                installerActive = false
                ollamaSource = await OllamaInstaller.shared.currentSource()
                await OllamaService.shared.startServer()
            case .failed(let msg):
                installerActive = false
                installerStatus = msg
                lastError = msg
            }
        }
    }

    private func observeOllamaState() async {
        var wasRunning = false
        for await state in await OllamaService.shared.stateStream() {
            self.ollamaState = state
            // Pre-warm the active model the moment the engine becomes ready, so
            // the first real suggestion is instant instead of paying the
            // multi-second cold-load. (Warm inference is ~0.3s; a cold load is
            // ~8s.) Only fire on the transition into running.
            if state == .running, !wasRunning {
                prewarmActiveModel()
            }
            wasRunning = (state == .running)
        }
    }

    /// Fire-and-forget 1-token request to load the active model into memory and
    /// reset its keep-alive timer.
    func prewarmActiveModel() {
        let model = UserPreferences.shared.activeModelTag
        guard !model.isEmpty else { return }
        Task.detached {
            await ModelManager.warm(model: model)
        }
    }

    /// Called by `UserPreferences.activeModelTag` when the user picks another
    /// model: frees the previous one (it would otherwise stay resident for its
    /// 30-minute keep-alive) and pre-loads the new one, so the first
    /// suggestion after switching doesn't pay the cold load.
    func activeModelDidChange(from old: String) {
        let new = UserPreferences.shared.activeModelTag
        guard old != new, !new.isEmpty,
              UserPreferences.shared.engine == "ollama",
              ollamaState == .running
        else { return }
        Task.detached {
            if !old.isEmpty {
                await ModelManager.unload(model: old)
            }
            await ModelManager.warm(model: new)
        }
    }

    private nonisolated static func warm(model: String) async {
        var req = URLRequest(url: Constants.Ollama.generateURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // A cold load of a large model can take a while; don't hang forever.
        req.timeoutInterval = LLMDeadline.prewarm
        let body: [String: Any] = [
            "model": model,
            "prompt": " ",
            "stream": false,
            "think": false,
            "keep_alive": "30m",
            "options": ["num_predict": 1],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Asks Ollama to evict `model` now (`keep_alive: 0`). Errors are ignored.
    private nonisolated static func unload(model: String) async {
        var req = URLRequest(url: Constants.Ollama.generateURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body: [String: Any] = [
            "model": model,
            "prompt": "",
            "stream": false,
            "keep_alive": 0,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func observeInstalledModels() async {
        for await models in await OllamaService.shared.installedModelsStream() {
            let tags = Set(models.map { $0.name })
            // Treat "gemma3:4b" and "gemma3:4b:latest" as equivalent for UI purposes.
            var normalized = tags
            for t in tags where t.hasSuffix(":latest") {
                let stripped = String(t.dropLast(":latest".count))
                normalized.insert(stripped)
            }
            self.installedTags = normalized
        }
    }

    func status(for entry: ModelEntry, activeTag: String) -> QModelCardStatus {
        if let progress = activeDownloads[entry.ollamaTag] {
            return .downloading(progress: progress)
        }
        let installed = installedTags.contains(entry.ollamaTag) ||
                        installedTags.contains(entry.ollamaTag + ":latest")
        if installed && entry.ollamaTag == activeTag { return .active }
        if installed { return .installed }
        return .notInstalled
    }

    func startDownload(_ entry: ModelEntry) {
        guard activeDownloads[entry.ollamaTag] == nil else { return }
        activeDownloads[entry.ollamaTag] = 0
        downloadStatusText[entry.ollamaTag] = "Starting download…"

        Task {
            let stream = await OllamaService.shared.download(tag: entry.ollamaTag)
            for await event in stream {
                switch event {
                case .started:
                    activeDownloads[entry.ollamaTag] = 0
                    downloadStatusText[entry.ollamaTag] = "Reaching the engine…"
                case .progress(let fraction, let statusText):
                    if fraction > 0 {
                        activeDownloads[entry.ollamaTag] = fraction
                    }
                    downloadStatusText[entry.ollamaTag] = statusText
                case .completed:
                    activeDownloads.removeValue(forKey: entry.ollamaTag)
                    downloadStatusText.removeValue(forKey: entry.ollamaTag)
                    _ = await OllamaService.shared.refreshInstalledModels()
                    // Picked before it finished downloading (onboarding) —
                    // load it now that it exists.
                    if entry.ollamaTag == UserPreferences.shared.activeModelTag {
                        prewarmActiveModel()
                    }
                case .failed(let msg):
                    lastError = msg
                    activeDownloads.removeValue(forKey: entry.ollamaTag)
                    downloadStatusText.removeValue(forKey: entry.ollamaTag)
                    // "Engine unavailable. …" carries raw engine stderr, which
                    // must never reach the log — only its size.
                    let logged = msg.hasPrefix("Engine unavailable.")
                        ? "engine unavailable (\(msg.count) chars)" : msg
                    QLog.error(.engine, "download failed for \(entry.ollamaTag) — \(logged)")
                case .cancelled:
                    activeDownloads.removeValue(forKey: entry.ollamaTag)
                    downloadStatusText.removeValue(forKey: entry.ollamaTag)
                }
            }
        }
    }

    func cancelDownload(_ entry: ModelEntry) {
        Task { await OllamaService.shared.cancelDownload(tag: entry.ollamaTag) }
    }

    func deleteModel(_ entry: ModelEntry) {
        Task {
            do {
                try await OllamaService.shared.deleteModel(tag: entry.ollamaTag)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Returns true if RAM is insufficient for the model (less than 75% of model needs).
    func isRAMInsufficient(for entry: ModelEntry) -> Bool {
        detectedRAMGB * 0.75 < entry.ramGB
    }
}
