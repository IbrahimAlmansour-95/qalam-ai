import Foundation
import FoundationModels

/// LLMBackend backed by Apple Intelligence's on-device Foundation Model
/// (macOS 26+). Zero download, system-managed, very low latency. Availability
/// is gated at runtime; callers should check `AppleIntelligenceBackend.isAvailable`
/// and fall back to Ollama otherwise.
struct AppleIntelligenceBackend: LLMBackend {

    /// Whether the on-device Foundation Model is usable right now (correct OS,
    /// Apple Intelligence enabled, model downloaded, device supported).
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        return false
    }

    /// Human-readable reason the model isn't available, for the Settings UI.
    static var unavailableReason: String? {
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings."
            case .unavailable(.modelNotReady):
                return "The Apple Intelligence model is still downloading."
            case .unavailable(.deviceNotEligible):
                return "This Mac doesn't support Apple Intelligence."
            case .unavailable:
                return "Apple Intelligence is unavailable."
            @unknown default:
                return "Apple Intelligence is unavailable."
            }
        }
        return "Requires macOS 26 or later."
    }

    func complete(
        prompt: String,
        model: String,
        maxTokens: Int,
        temperature: Double,
        stop: [String]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard #available(macOS 26.0, *), AppleIntelligenceBackend.isAvailable else {
                continuation.finish(throwing: NSError(
                    domain: "QalamAI.AppleIntelligence", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        AppleIntelligenceBackend.unavailableReason ?? "Unavailable"]))
                return
            }

            let task = Task {
                do {
                    let session = LanguageModelSession()
                    let options = GenerationOptions(
                        temperature: temperature,
                        maximumResponseTokens: maxTokens
                    )
                    // Stream cumulative snapshots; yield only the new delta so
                    // the SuggestionEngine sees incremental tokens like Ollama.
                    let responseStream = session.streamResponse(to: prompt, options: options)
                    var emitted = ""
                    for try await snapshot in responseStream {
                        try Task.checkCancellation()
                        let full = snapshot.content
                        guard full.count > emitted.count else { continue }
                        let startIdx = full.index(full.startIndex, offsetBy: emitted.count)
                        continuation.yield(String(full[startIdx...]))
                        emitted = full
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
