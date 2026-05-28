import Foundation
import AppKit
import SwiftUI

@MainActor
enum OnboardingWindowController {
    static func make() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Qalam"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.isMovableByWindowBackground = true

        let host = NSHostingController(rootView: OnboardingView())
        window.contentViewController = host
        return NSWindowController(window: window)
    }
}
