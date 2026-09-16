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
        // A second copy activates the running one and exits here — before it
        // touches the menu bar, the keystroke tap or the engine.
        guard SingleInstance.enforce() else { return }
        SingleInstance.observeActivationRequests()

        let os = ProcessInfo.processInfo.operatingSystemVersion
        QLog.notice(.app, "launch v\(Constants.version) (macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion))")
        // Local crash/hang reports (MetricKit) — kept on this Mac only.
        DiagnosticsCollector.shared.start()

        NSApp.setActivationPolicy(.accessory)
        installEditMenu()
        // Touch UserPreferences early so first-launch timestamp persists.
        _ = UserPreferences.shared.firstLaunchDate
        // Per-app / per-site profiles: one-time migration of the old
        // excluded-apps list, before anything reads activation state.
        ProfileStore.shared.start()
        // Re-applies "Improve compatibility" (Electron accessibility) when an
        // app the user enabled it for launches or comes forward.
        ElectronCompatibility.shared.start()

        // Apply the saved theme (Light / Dark / System) before any window shows.
        AppearanceManager.applyCurrent()

        // Menu bar lives first so the user has a way to recover even if
        // permissions aren't granted yet.
        MenuBarController.shared.install()

        // Start model manager + Ollama service.
        ModelManager.shared.start()
        Task { await OllamaService.shared.startServer() }

        // Suggestion + keystroke pipeline. The AX messaging timeout goes in
        // before the tap (and any AX call) so a hung app can never freeze
        // typing.
        SuggestionEngine.shared.start()
        // Personalization: watches the same context stream. Recording is off
        // by default, and the encrypted store is only opened (keychain read
        // included) when the feature is actually in use.
        WritingRecorder.shared.start()
        if UserPreferences.shared.recordWritingEnabled ||
           UserPreferences.shared.personalizationStrength != .off {
            Task.detached { await PersonalizationStore.shared.loadIfNeeded() }
        }
        // Encrypted iCloud Drive sync. Off by default; with sync off this
        // does nothing and never looks at ~/Library/Mobile Documents.
        SyncManager.shared.start()
        SecureInputMonitor.shared.start()
        AXGuard.configureGlobalTimeout()
        KeystrokeInterceptor.shared.install()
        OverlayCoordinator.shared.start()

        // Accessibility permission. macOS Tahoe invalidates ad-hoc grants on
        // every rebuild, so the user has to re-grant after each reinstall.
        // Watch for the grant; reinstall the keystroke tap when it flips on so
        // autocomplete starts working again without an app restart.
        AccessibilityPermissionMonitor.shared.start()
        AccessibilityPermissionMonitor.shared.onGrantedTransition {
            QLog.notice(.app, "Accessibility just granted — reinstalling keystroke tap")
            AXGuard.configureGlobalTimeout()
            KeystrokeInterceptor.shared.uninstall()
            KeystrokeInterceptor.shared.install()
        }

        // Check GitHub for updates (opt-out in Settings).
        UpdateChecker.shared.start()

        // First-run onboarding.
        if !UserPreferences.shared.hasCompletedOnboarding {
            AppState.shared.showOnboarding()
        } else if !AccessibilityMonitor.shared.checkPermission() {
            // Returning user, but Accessibility isn't trusted — almost always
            // because an app update changed the (ad-hoc) code signature and
            // macOS dropped the grant. Trigger the system prompt so QalamAI
            // reappears in the Accessibility list and the user can re-enable it
            // with one toggle, instead of having to hunt for the menu button.
            _ = AccessibilityMonitor.shared.checkPermission(prompt: true)
            AppState.shared.showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A duplicate launch exits via exit(0) and never gets here; guard
        // anyway so it can never stop the running copy's engine.
        if SingleInstance.isDuplicate { return }
        QLog.notice(.app, "terminating")
        KeystrokeInterceptor.shared.uninstall()
        OverlayCoordinator.shared.hideAll()
        ProfileStore.shared.flushPendingSave()
        SyncManager.shared.stopActivity()
        SyncMetadata.shared.flushPendingSave()
        // Quitting: the engine's exit below is intentional — don't restart it.
        OllamaService.shutdownFlag.set()
        // Stop the bundled Ollama engine we launched, otherwise it (and its
        // model-loaded runner children) are orphaned on every quit — they pile
        // up across launches and thrash memory, making suggestions crawl.
        // Synchronous + path-scoped so it runs during termination and never
        // touches a system Ollama.
        OllamaService.killBundledEngine()
        QLog.flush()
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

    /// Accessory apps get no main menu, so ⌘C / ⌘V / ⌘A / ⌘Z did nothing in
    /// our own text fields (instructions, website, snippets). A hidden Edit
    /// menu gives them the standard key equivalents. Titles are the system's
    /// English ones; the menu is never shown for an accessory app.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
}
