import Foundation

/// Thrown when a model call runs past its overall deadline.
struct LLMTimeoutError: LocalizedError, Sendable {
    let seconds: TimeInterval
    /// English, for logs only — user-facing UI uses a localized string.
    var errorDescription: String? { "The model did not respond in time." }
}

/// Overall deadlines per kind of model call. The HTTP idle timeout in
/// `OllamaBackend` only catches a silent connection; these also bound a
/// stream that keeps trickling (or an Apple Intelligence session that never
/// finishes).
enum LLMDeadline {
    /// Inline completion — a warm model answers in well under a second; this
    /// leaves room for a cold model load.
    static let completion: TimeInterval = 12
    /// Sentence proof-read before a completion.
    static let proofread: TimeInterval = 10
    /// User-initiated tone rewrite of a selection (up to 512 tokens).
    static let rewrite: TimeInterval = 60
    /// Alternative next-word lookups.
    static let alternatives: TimeInterval = 8
    /// Pre-warm request — a cold load of a large model can take a while.
    static let prewarm: TimeInterval = 120
}

extension LLMBackend {
    /// `complete(...)` bounded by an overall `deadline` in seconds. On timeout
    /// the underlying request is cancelled and the stream finishes by throwing
    /// `LLMTimeoutError`; cancelling the consumer cancels both.
    func complete(
        prompt: String,
        model: String,
        maxTokens: Int,
        temperature: Double,
        stop: [String],
        deadline: TimeInterval
    ) -> AsyncThrowingStream<String, Error> {
        let inner = complete(prompt: prompt, model: model, maxTokens: maxTokens,
                             temperature: temperature, stop: stop)
        return AsyncThrowingStream { continuation in
            let forward = Task {
                do {
                    for try await token in inner {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, deadline) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                // Finish with the timeout FIRST so the forwarder's own
                // cancellation-driven `finish()` can't turn it into a normal end.
                continuation.finish(throwing: LLMTimeoutError(seconds: deadline))
                forward.cancel()
            }
            continuation.onTermination = { _ in
                forward.cancel()
                watchdog.cancel()
            }
        }
    }
}
