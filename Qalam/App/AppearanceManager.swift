import AppKit

/// Applies the user's theme choice ("system" / "light" / "dark") globally by
/// setting `NSApp.appearance`. QColors are dynamic NSColors, so all SwiftUI
/// views and AppKit panels re-resolve automatically when this changes.
@MainActor
enum AppearanceManager {
    /// Call once at launch (after prefs load) and whenever the pref changes.
    static func apply(_ raw: String) {
        let appearance: NSAppearance?
        switch raw {
        case "light": appearance = NSAppearance(named: .aqua)
        case "dark":  appearance = NSAppearance(named: .darkAqua)
        default:      appearance = nil   // follow the system
        }
        NSApp.appearance = appearance
        // Setting NSApp.appearance alone doesn't reliably re-render windows that
        // are already on screen (the Settings window, menu-bar popover, overlay
        // panels), so push the appearance onto every existing window too. Their
        // SwiftUI content then re-resolves the dynamic QColors immediately.
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }

    /// Convenience: apply the current preference.
    static func applyCurrent() {
        apply(UserPreferences.shared.appearance)
    }
}
