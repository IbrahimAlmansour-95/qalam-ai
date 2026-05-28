import Foundation
import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private init() {}

    /// Loads the bundled menu-bar icon (the قلم calligraphy as a template
    /// image). Pairs MenuBarIcon.png (1×) with MenuBarIcon@2x.png so Retina
    /// menu bars render sharply.
    private static func loadStatusIcon() -> NSImage? {
        // NSImage(named:) auto-resolves @2x when the files sit in Resources/.
        if let img = NSImage(named: "MenuBarIcon") {
            img.isTemplate = true
            // Match the natural status item glyph size on macOS Big Sur+.
            img.size = NSSize(width: 18, height: 18)
            return img
        }

        // Manual fallback: build an NSImage that owns both reps.
        guard let url1x = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let img = NSImage(contentsOf: url1x)
        else { return nil }
        img.size = NSSize(width: 18, height: 18)
        if let url2x = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
           let img2x = NSImage(contentsOf: url2x),
           let rep2x = img2x.representations.first {
            rep2x.size = NSSize(width: 18, height: 18)
            img.addRepresentation(rep2x)
        }
        img.isTemplate = true
        return img
    }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Try to load the bundled قلم calligraphy first; fall back to an
            // SF Symbol if for any reason the resource is missing.
            let img: NSImage? = MenuBarController.loadStatusIcon()
                ?? NSImage(systemSymbolName: "character.bubble",
                           accessibilityDescription: Constants.appName)
            img?.isTemplate = true
            button.image = img
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 320, height: 420)
        pop.contentViewController = NSHostingController(rootView: MenuBarPopoverView())
        popover = pop
    }

    func uninstall() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        popover = nil
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Pops the menu bar popover open (used right after onboarding so the
    /// user immediately sees where the app lives).
    func flashAndShow() {
        guard let button = statusItem?.button, let popover else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
