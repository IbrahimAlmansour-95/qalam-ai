import Foundation
import AppKit
import SwiftUI

/// Optional small QalamAI badge at the top corner of the focused text field
/// (off by default). Clicking it opens a short menu — turn QalamAI off in this
/// app, pause it for ten minutes, or open that app's settings.
///
/// It is deliberately unobtrusive: it never becomes the key window (so the
/// app the user is typing in keeps focus), it is hidden while they type,
/// while a suggestion or the alternatives list is on screen, in password
/// fields, and whenever it would sit on top of the caret, the ghost text,
/// the mirror bubble or that list.
@MainActor
final class FieldButtonPanel {
    static let shared = FieldButtonPanel()

    private let panel: NonKeyPanel
    private let button: FieldButtonView
    private var isShown = false
    /// The badge's menu is open — the panel must stay where it is until the
    /// user has chosen (the overlay loop keeps ticking during menu tracking).
    private var menuIsOpen = false

    private static let diameter: CGFloat = 18
    /// Quiet time after the last keystroke before the badge may appear.
    private static let idleSeconds: TimeInterval = 1.2
    private static let minFieldWidth: CGFloat = 120
    private static let minFieldHeight: CGFloat = 18
    /// Clearance kept around the caret / ghost / bubble.
    private static let clearance: CGFloat = 6

    private init() {
        let view = FieldButtonView(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        button = view
        let p = NonKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.becomesKeyOnlyIfNeeded = true
        p.ignoresMouseEvents = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.contentView = view
        p.alphaValue = 0
        panel = p
    }

    /// The user is typing: get out of the way now (cheap no-op when hidden, it
    /// runs from the keystroke tap).
    func noteTyping() {
        guard isShown, !menuIsOpen else { return }
        hide()
    }

    fileprivate func setMenuOpen(_ open: Bool) {
        menuIsOpen = open
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    /// Re-evaluates visibility and position. Called from the overlay loop a
    /// few times a second with the last field context that was read.
    func update(context: TextContext?) {
        guard !menuIsOpen else { return }
        guard UserPreferences.shared.showFieldButton,
              !SecureInputMonitor.shared.isActive,
              !OverlayCoordinator.shared.isSuggestionVisible,
              !AlternativesPanel.shared.isVisible,
              let context, context != .empty,
              let bundleID = context.appBundleID, bundleID != Constants.bundleID,
              context.role != "AXSecureTextField", context.subrole != "AXSecureTextField",
              Date().timeIntervalSince(KeystrokeInterceptor.shared.lastKeyDownAt) >= Self.idleSeconds
        else {
            hide()
            return
        }
        // The context may be a moment old; don't draw over a different app.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            hide()
            return
        }
        let pid = AXGuard.frontmostPID()
        guard !AXGuard.isBackedOff(pid) else {
            hide()
            return
        }
        let monitor = AccessibilityMonitor.shared
        let (field, caret) = AXGuard.measure(pid: pid) {
            (monitor.focusedFrame(), monitor.caretFrame())
        }
        guard let field, field.width >= Self.minFieldWidth, field.height >= Self.minFieldHeight else {
            hide()
            return
        }

        // The app's own writing direction, from the text in the field.
        let isRTL = Script.firstStrong(in: context.fullText.prefix(200)) == .arabic
        var rect = Self.cornerRect(field: field, isRTL: isRTL)
        if blocked(rect, caret: caret) {
            rect = Self.sideRect(field: field, isRTL: isRTL)
            if blocked(rect, caret: caret) {
                hide()
                return
            }
        }
        guard Self.fitsOnScreen(rect) else {
            hide()
            return
        }
        show(rect, bundleID: bundleID, appName: context.appName ?? bundleID)
    }

    // MARK: - Private

    private func show(_ rect: NSRect, bundleID: String, appName: String) {
        button.bundleID = bundleID
        button.appName = appName
        panel.setFrame(rect, display: true)
        panel.alphaValue = 1
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        isShown = true
    }

    /// True when the badge would sit on the caret, the ghost or the bubble.
    private func blocked(_ rect: NSRect, caret: CGRect?) -> Bool {
        let padded = rect.insetBy(dx: -Self.clearance, dy: -Self.clearance)
        if let caret, padded.intersects(caret) { return true }
        if GhostTextOverlayWindow.shared.isVisible,
           padded.intersects(GhostTextOverlayWindow.shared.frame) { return true }
        if MirrorBubblePanel.shared.isVisible,
           padded.intersects(MirrorBubblePanel.shared.frame) { return true }
        if AlternativesPanel.shared.isVisible,
           padded.intersects(AlternativesPanel.shared.frame) { return true }
        return false
    }

    /// Preferred spot: just above the field's trailing corner.
    private static func cornerRect(field: CGRect, isRTL: Bool) -> NSRect {
        NSRect(x: isRTL ? field.minX : field.maxX - diameter,
               y: field.maxY + 2, width: diameter, height: diameter)
    }

    /// Fallback: outside the field's trailing edge, level with its top.
    private static func sideRect(field: CGRect, isRTL: Bool) -> NSRect {
        NSRect(x: isRTL ? field.minX - diameter - 4 : field.maxX + 4,
               y: field.maxY - diameter, width: diameter, height: diameter)
    }

    private static func fitsOnScreen(_ rect: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.contains(rect) }
    }
}

/// A panel that can never take keyboard focus away from the app being typed in.
final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the badge (SwiftUI) but handles the click itself, so the menu opens
/// from a plain AppKit mouse-down and the hosting view never swallows it.
final class FieldButtonView: NSView {
    var bundleID: String = ""
    var appName: String = ""

    private let hosting: NSHostingView<FieldButtonBadge>

    override init(frame frameRect: NSRect) {
        hosting = NSHostingView(rootView: FieldButtonBadge())
        super.init(frame: frameRect)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FieldButtonView is created in code only")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard !bundleID.isEmpty else { return }
        let menu = NSMenu()
        let isOff = ProfileStore.shared.appProfile(bundleID: bundleID)?.activation == .off
        let toggle = NSMenuItem(
            title: String(format: L.t(isOff ? .fieldButtonEnableFmt : .fieldButtonDisableFmt), appName),
            action: #selector(toggleApp), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let pause = NSMenuItem(title: L.t(.fieldButtonPause10), action: #selector(pauseApp), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: L.t(.fieldButtonSettings), action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        // `popUp` tracks the menu in a nested run loop, so the overlay loop
        // keeps running: freeze the badge until the user has chosen.
        FieldButtonPanel.shared.setMenuOpen(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        FieldButtonPanel.shared.setMenuOpen(false)
    }

    // MARK: - Menu actions

    @objc private func toggleApp() {
        let store = ProfileStore.shared
        store.ensureApp(bundleID: bundleID, name: appName)
        let id = AppProfile.appID(bundleID)
        let isOff = store.profile(id: id)?.activation == .off
        store.update(id: id) { $0.activation = isOff ? nil : ProfileActivation.off }
        if !isOff { SuggestionEngine.shared.dismiss() }
        MenuBarController.shared.refreshStatusAppearance()
        FieldButtonPanel.shared.hide()
    }

    @objc private func pauseApp() {
        TemporaryPauseStore.shared.pause(bundleID: bundleID, minutes: 10)
        SuggestionEngine.shared.dismiss()
        MenuBarController.shared.refreshStatusAppearance()
        StatusToastPanel.shared.show(String(format: L.t(.toastPausedAppFmt), appName), icon: "pause.circle")
        FieldButtonPanel.shared.hide()
    }

    @objc private func openSettings() {
        ProfileStore.shared.ensureApp(bundleID: bundleID, name: appName)
        FieldButtonPanel.shared.hide()
        AppState.shared.showSettings(tab: .apps, profileID: AppProfile.appID(bundleID))
    }
}

struct FieldButtonBadge: View {
    var body: some View {
        ZStack {
            Circle().fill(QColors.backgroundElevated)
            Circle().strokeBorder(QColors.borderMedium, lineWidth: 1)
            QalamLogo(size: 11, tint: QColors.accent)
        }
    }
}
