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
        }
        guard let wc = onboardingWindowController else { return }
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
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
