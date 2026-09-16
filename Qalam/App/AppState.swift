import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var settingsWindowController: NSWindowController?
    var onboardingWindowController: NSWindowController?

    /// Tab / profile to show when Settings opens (or is already open).
    /// `SettingsView` and `AppsSettingsView` apply these, then clear them.
    var requestedSettingsTab: SettingsTab?
    var requestedProfileID: String?

    private init() {}

    func showSettings(tab: SettingsTab? = nil, profileID: String? = nil) {
        if let tab { requestedSettingsTab = tab }
        if let profileID { requestedProfileID = profileID }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController.make()
        }
        guard let wc = settingsWindowController else { return }
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController.make()
            observeOnboardingClose()
        }
        guard let wc = onboardingWindowController else { return }
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
    }

    @ObservationIgnored private var onboardingCloseObserver: NSObjectProtocol?

    /// The onboarding window is kept alive after closing (`isReleasedWhenClosed
    /// = false`), so closing it with the title-bar button used to leave its
    /// animated background and poll timers running for the rest of the session
    /// (~25% CPU). Release it whenever it closes, by any route.
    private func observeOnboardingClose() {
        guard let window = onboardingWindowController?.window else { return }
        if let stale = onboardingCloseObserver {
            NotificationCenter.default.removeObserver(stale)
        }
        let windowID = ObjectIdentifier(window)
        onboardingCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            // Next turn, so the window finishes closing before it's released.
            Task { @MainActor in AppState.shared.releaseOnboardingWindow(windowID) }
        }
    }

    /// Detaching the SwiftUI view stops its animation and fires `onDisappear`,
    /// which invalidates the poll timers. Setup is NOT marked complete here —
    /// only `dismissOnboarding()` does that — so an unfinished setup still
    /// reopens on the next launch.
    private func releaseOnboardingWindow(_ windowID: ObjectIdentifier) {
        // Reopened in the meantime: the new window has its own observer.
        if let current = onboardingWindowController?.window,
           ObjectIdentifier(current) != windowID { return }
        if let observer = onboardingCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            onboardingCloseObserver = nil
        }
        onboardingWindowController?.window?.contentViewController = nil
        onboardingWindowController = nil
    }

    func dismissOnboarding() {
        onboardingWindowController?.close()
        onboardingWindowController = nil
        UserPreferences.shared.hasCompletedOnboarding = true

        // Briefly highlight the menu bar so the user knows where to find us
        // and can watch any in-flight model download.
        MenuBarController.shared.flashAndShow()
    }
}
