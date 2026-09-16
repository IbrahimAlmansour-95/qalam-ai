import Foundation
import Observation
import AppKit
import Carbon

/// Tracks macOS Secure Event Input (turned on by password fields, Terminal's
/// "Secure Keyboard Entry", some password managers). While it's on the
/// keystroke tap receives no key events, so the state has to be polled.
/// Consumers pause suggestions and corrections and hide the ghost; the menu
/// bar popover explains why.
@MainActor
@Observable
final class SecureInputMonitor {
    static let shared = SecureInputMonitor()

    private(set) var isActive: Bool = false
    private var pollTimer: Timer?

    private init() {}

    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in SecureInputMonitor.shared.tick() }
        }
        tick()
    }

    private func tick() {
        let now = Self.isSecureEventInputEnabled()
        guard now != isActive else { return }
        isActive = now
        QLog.notice(.input, "Secure Input \(now ? "on — suggestions paused" : "off — suggestions resumed")")
        if now {
            SuggestionEngine.shared.dismiss()
            OverlayCoordinator.shared.hideAll()
        }
    }

    /// `IsSecureEventInputEnabled()` (HIToolbox, linked via Carbon) is no longer
    /// declared in the SDK headers, but the symbol is still exported. Resolve it
    /// once at runtime; if it's ever missing, report "off" (today's behaviour).
    private typealias SecureInputFn = @convention(c) () -> UInt8
    private static let secureInputFn: SecureInputFn? = {
        // RTLD_DEFAULT is a C macro ((void *)-2) that Swift doesn't import.
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IsSecureEventInputEnabled")
        else { return nil }
        return unsafeBitCast(sym, to: SecureInputFn.self)
    }()

    private static func isSecureEventInputEnabled() -> Bool {
        guard let fn = secureInputFn else { return false }
        return fn() != 0
    }
}
