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
                    } else if let caret = AccessibilityMonitor.shared.caretFrame() {
                        let hint = AppDelegate.hint(for: suggestion)
                        let style = AccessibilityMonitor.shared.caretStyle()
                        let rtl = AppDelegate.isRTLText(text)
                        GhostTextOverlayWindow.shared.update(
                            text: text, hint: hint, style: style, caret: caret, isRTL: rtl)
                    } else {
                        // No trustworthy caret (e.g. Electron canvas editors) —
                        // hide rather than draw at a wrong location.
                        GhostTextOverlayWindow.shared.hide()
                    }
                }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }

    /// True when the suggestion text is predominantly Arabic (RTL). Drives
    /// both the overlay's placement (left of caret) and its layout direction.
    private static func isRTLText(_ text: String) -> Bool {
        var rtl = 0, ltr = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v) ||
               (0xFB50...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) {
                rtl += 1
            } else if (0x0041...0x005A).contains(v) || (0x0061...0x007A).contains(v) {
                ltr += 1
            }
        }
        return rtl > ltr
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
