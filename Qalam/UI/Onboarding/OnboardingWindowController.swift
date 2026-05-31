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
        // Keep the window stationary. Dragging by the background made the
        // onboarding window drift/"float" when clicking its content, which made
        // the Get Started button hard to press. It still moves by its title bar.
        window.isMovableByWindowBackground = false

        let host = NSHostingController(rootView: OnboardingView())
        window.contentViewController = host
        return NSWindowController(window: window)
    }
}
