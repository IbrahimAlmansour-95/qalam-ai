import Foundation

actor Debouncer {
    private var pending: Task<Void, Never>?

    init() {}

    /// Runs `action` after `delayMs` unless another `schedule`/`cancel` comes
    /// first. The delay is passed per call so the Settings slider applies live.
    /// Clamped to 0…2000 ms; 0 runs on the next task hop.
    func schedule(delayMs: Int, _ action: @escaping @Sendable () async -> Void) {
        pending?.cancel()
        let delay = UInt64(min(max(delayMs, 0), 2000))
        pending = Task {
            do {
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay * 1_000_000)
                } else {
                    await Task.yield()
                }
                try Task.checkCancellation()
                await action()
            } catch { /* cancelled */ }
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
