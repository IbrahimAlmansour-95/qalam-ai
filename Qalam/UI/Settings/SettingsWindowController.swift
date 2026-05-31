import Foundation
import AppKit
import SwiftUI

@MainActor
enum SettingsWindowController {
    static func make() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(Constants.appName) Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 860, height: 580)
        // Follow the user's theme (System/Light/Dark) instead of forcing dark.
        switch UserPreferences.shared.appearance {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark":  window.appearance = NSAppearance(named: .darkAqua)
        default:      window.appearance = nil
        }
        // Solid background prevents the "empty window" render seen on first
        // open (the NSVisualEffectView path left content blank on macOS 26.5).
        // DYNAMIC so the title bar (transparent → shows the window background)
        // matches the theme instead of showing a hardcoded dark strip.
        window.backgroundColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 18/255, green: 18/255, blue: 20/255, alpha: 1)
                : NSColor(srgbRed: 250/255, green: 250/255, blue: 252/255, alpha: 1)
        }
        window.isOpaque = true

        let host = NSHostingController(rootView: SettingsView())
        window.contentViewController = host
        return NSWindowController(window: window)
    }
}
