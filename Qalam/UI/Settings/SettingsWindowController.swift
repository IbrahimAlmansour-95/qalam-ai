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
        window.appearance = NSAppearance(named: .darkAqua)
        // Solid background prevents the "empty window" render seen on first
        // open — the NSVisualEffectView path was leaving the content blank on
        // macOS 26.5.
        window.backgroundColor = NSColor(red: 18/255, green: 18/255, blue: 20/255, alpha: 1)
        window.isOpaque = true

        let host = NSHostingController(rootView: SettingsView())
        window.contentViewController = host
        return NSWindowController(window: window)
    }
}
