import Foundation
import Observation
import AppKit
import ApplicationServices

/// Observable wrapper around AX trust state. macOS Tahoe revokes the
/// Accessibility grant whenever an ad-hoc signed binary changes — every fresh
/// build of QalamAI starts ungranted. This monitor:
///   * exposes `isGranted` for the UI
///   * polls the system every 2 s
///   * notifies on transitions (denied → granted) so we can re-install the
///     CGEventTap without an app restart
@MainActor
@Observable
final class AccessibilityPermissionMonitor {
    static let shared = AccessibilityPermissionMonitor()

    private(set) var isGranted: Bool = false
    private var pollTimer: Timer?
    private var transitionHandlers: [() -> Void] = []

    private init() {
        self.isGranted = AccessibilityMonitor.shared.checkPermission()
    }

    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func tick() {
        let now = AccessibilityMonitor.shared.checkPermission()
        let wasGranted = isGranted
        if now != isGranted {
            isGranted = now
            if !wasGranted && now {
                // Permission was just granted — fire handlers (e.g. reinstall tap).
                for h in transitionHandlers { h() }
            }
        }
    }

    /// Register a callback that runs every time the user flips permission
    /// from denied to granted.
    func onGrantedTransition(_ handler: @escaping () -> Void) {
        transitionHandlers.append(handler)
    }

    /// Open System Settings → Privacy & Security → Accessibility.
    func openSystemSettings() {
        AccessibilityMonitor.shared.openSystemSettings()
        // Pop the trust dialog if the system hasn't recently shown one.
        _ = AccessibilityMonitor.shared.checkPermission(prompt: true)
    }
}
