import AppKit
import SwiftUI

/// Plain @main entry. We deliberately do NOT use `struct QalamApp: App` because
/// SwiftUI App's `Settings { EmptyView() }` Scene auto-opens on macOS Tahoe
/// during accessory-app activation and shows as a blank "QalamAI Settings"
/// window the first time the app launches. Going through NSApplication directly
/// gives us full control over which windows ever appear.
@main
@MainActor
enum QalamAIMain {
    /// Held strongly because `NSApplication.delegate` is `weak`.
    static var delegateStrongRef: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        delegateStrongRef = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Touch UserPreferences early so first-launch timestamp persists.
        _ = UserPreferences.shared.firstLaunchDate

        // Menu bar lives first so the user has a way to recover even if
        // permissions aren't granted yet.
        MenuBarController.shared.install()

        // Start model manager + Ollama service.
        ModelManager.shared.start()
        Task { await OllamaService.shared.startServer() }

        // Suggestion + keystroke pipeline.
        SuggestionEngine.shared.start()
        KeystrokeInterceptor.shared.install()
        bindGhostOverlay()
        bindPauseShortcut()

        // Accessibility permission. macOS Tahoe invalidates ad-hoc grants on
        // every rebuild, so the user has to re-grant after each reinstall.
        // Watch for the grant; reinstall the keystroke tap when it flips on so
        // autocomplete starts working again without an app restart.
        AccessibilityPermissionMonitor.shared.start()
        AccessibilityPermissionMonitor.shared.onGrantedTransition {
            NSLog("QalamAI: Accessibility just granted — reinstalling keystroke tap")
            KeystrokeInterceptor.shared.uninstall()
            KeystrokeInterceptor.shared.install()
        }

        // First-run onboarding.
        if !UserPreferences.shared.hasCompletedOnboarding {
            AppState.shared.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeystrokeInterceptor.shared.uninstall()
        GhostTextOverlayWindow.shared.hide()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Menu-bar app: ignore reopen requests so closing the onboarding window
        // doesn't auto-pop the Settings window. The user accesses us via the
        // menu bar icon.
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Ghost overlay observation

    private var observerTask: Task<Void, Never>?

    private func bindGhostOverlay() {
        observerTask = Task { @MainActor [weak self] in
            guard self != nil else { return }
            var lastText = ""
            while !Task.isCancelled {
                let suggestion = SuggestionEngine.shared.currentSuggestion
                let text = suggestion?.text ?? ""
                if text != lastText {
                    lastText = text
                    if text.isEmpty {
                        GhostTextOverlayWindow.shared.hide()
                    } else {
                        let hint = AppDelegate.hint(for: suggestion)
                        let point = AppDelegate.overlayAnchor()
                        if let point {
                            GhostTextOverlayWindow.shared.update(text: text, hint: hint, screenPoint: point)
                        } else {
                            GhostTextOverlayWindow.shared.hide()
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }

    /// Decides where the ghost-text overlay should appear.
    /// Strategy ladder:
    ///   1. Real AX caret bounds (`kAXBoundsForRangeParameterizedAttribute`)
    ///      — works for native AppKit / Cocoa text fields.
    ///   2. Focused element's frame *top-left + small offset* — better than
    ///      bottom-left, which lands far below the actual caret in tall fields.
    ///   3. System mouse position — least accurate but at least near where the
    ///      user is interacting (helps with Electron apps that don't expose
    ///      caret bounds).
    /// Returns the (x, topY) where the ghost-text overlay's TOP-LEFT should
    /// sit in AppKit screen coords. The overlay then positions itself so the
    /// text's top aligns with the caret line's top — matching the typed text's
    /// visual line so the suggestion looks inline.
    private static func overlayAnchor() -> CGPoint? {
        if let caret = AccessibilityMonitor.shared.caretFrame(), caret.width >= 0 {
            // `caret.maxY` is the TOP of the caret line in AppKit (Y up).
            // Place the overlay's TOP-LEFT there, just to the right of the
            // caret's right edge.
            return CGPoint(x: caret.maxX + 1, y: caret.maxY)
        }
        if let frame = AccessibilityMonitor.shared.focusedFrame() {
            // No caret bounds (Cursor/VSCode/Electron). Place a hair below the
            // top of the focused area — close to first-line typing.
            return CGPoint(x: frame.minX + 8, y: frame.maxY - 4)
        }
        let mouse = NSEvent.mouseLocation
        guard mouse != .zero else { return nil }
        return CGPoint(x: mouse.x + 14, y: mouse.y)
    }

    private static func hint(for suggestion: SuggestionResult?) -> GhostStyleHint {
        guard let kind = suggestion?.kind else { return .completion }
        switch kind {
        case .llm: return .completion
        case .snippet: return .snippet
        case .emoji:   return .snippet
        case .correction(_, _, _, _, let issueKind):
            return issueKind == .spelling ? .spellingFix : .grammarFix
        }
    }

    /// Global ⌘⇧Space hotkey for pause/resume via a local CGEvent handler is
    /// already covered by KeystrokeInterceptor; this is the menu-side noop hook
    /// for future expansion.
    private func bindPauseShortcut() { /* reserved */ }
}
