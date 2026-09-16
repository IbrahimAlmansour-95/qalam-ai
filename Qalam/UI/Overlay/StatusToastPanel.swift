import Foundation
import AppKit
import SwiftUI

/// A short, click-through status capsule ("QalamAI paused", "Paused in Mail
/// for 10 minutes") shown after a global shortcut, since the user's focus is
/// in another app and the menu bar alone is easy to miss. Never activates
/// QalamAI, never takes clicks, fades out on its own.
@MainActor
final class StatusToastPanel {
    static let shared = StatusToastPanel()

    private let panel: NSPanel
    private let hosting: NSHostingController<StatusToastView>
    private let model: StatusToastModel
    /// Bumped per `show`, so an older fade-out never hides a newer toast.
    private var generation = 0

    private static let visibleSeconds: TimeInterval = 1.6
    private static let fadeSeconds: TimeInterval = 0.25
    private static let maxWidth: CGFloat = 480
    nonisolated fileprivate static let horizontalPadding: CGFloat = 14
    nonisolated fileprivate static let verticalPadding: CGFloat = 8
    nonisolated fileprivate static let iconWidth: CGFloat = 16
    nonisolated fileprivate static let iconSpacing: CGFloat = 8

    private init() {
        let m = StatusToastModel()
        model = m
        hosting = NSHostingController(rootView: StatusToastView(model: m))
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.contentViewController = hosting
        p.alphaValue = 0
        panel = p
    }

    /// Shows `message` (no user text — app names and static strings only)
    /// with an SF Symbol, centered on the screen under the mouse.
    func show(_ message: String, icon: String) {
        generation &+= 1
        let current = generation
        model.message = message
        model.icon = icon
        model.layoutDirection = LocalizationStore.shared.current.layoutDirection

        // Measured from the font (like the ghost), not the hosting view's
        // fitting size, which may still describe the previous message.
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let chrome = Self.horizontalPadding * 2 + Self.iconWidth + Self.iconSpacing
        let textBox = (message as NSString).boundingRect(
            with: CGSize(width: Self.maxWidth - chrome, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        let size = CGSize(width: min(Self.maxWidth, max(120, ceil(textBox.width) + chrome + 2)),
                          height: max(32, ceil(textBox.height) + Self.verticalPadding * 2))
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(x: frame.midX - size.width / 2,
                             y: frame.minY + frame.height * 0.18)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        // VoiceOver users don't see the capsule.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleSeconds) { [weak self] in
            MainActor.assumeIsolated {
                self?.fadeOut(ifGeneration: current)
            }
        }
    }

    private func fadeOut(ifGeneration expected: Int) {
        guard generation == expected else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeSeconds
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == expected else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}

@MainActor
final class StatusToastModel: ObservableObject {
    @Published var message = ""
    @Published var icon = "info.circle"
    @Published var layoutDirection: LayoutDirection = .leftToRight
}

struct StatusToastView: View {
    @ObservedObject var model: StatusToastModel

    var body: some View {
        HStack(spacing: StatusToastPanel.iconSpacing) {
            Image(systemName: model.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(QColors.textSecondary)
                .frame(width: StatusToastPanel.iconWidth)
            Text(model.message)
                .font(QFonts.bodyMed)
                .foregroundStyle(QColors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, StatusToastPanel.horizontalPadding)
        .padding(.vertical, StatusToastPanel.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QVisualEffect(material: .hudWindow))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(QColors.borderSubtle, lineWidth: 1))
        .environment(\.layoutDirection, model.layoutDirection)
    }
}
