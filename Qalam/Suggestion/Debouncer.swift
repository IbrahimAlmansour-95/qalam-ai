import Foundation

actor Debouncer {
    private var pending: Task<Void, Never>?
    private let interval: TimeInterval

    init(intervalMs: Int) {
        self.interval = Double(intervalMs) / 1000.0
    }

    func schedule(_ action: @escaping @Sendable () async -> Void) {
        pending?.cancel()
        let interval = self.interval
        pending = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
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
