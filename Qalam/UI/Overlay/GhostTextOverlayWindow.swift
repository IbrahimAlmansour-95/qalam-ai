import Foundation
import AppKit
import SwiftUI

/// Borderless, non-activating panel that draws ghost-text near the caret.
@MainActor
final class GhostTextOverlayWindow {
    static let shared = GhostTextOverlayWindow()

    private let panel: NSPanel
    private let hostingController: NSHostingController<GhostTextView>
    private let viewModel: GhostTextViewModel

    private init() {
        let vm = GhostTextViewModel()
        self.viewModel = vm
        let view = GhostTextView(model: vm)
        self.hostingController = NSHostingController(rootView: view)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.contentViewController = hostingController
        p.alphaValue = 0
        self.panel = p
    }

    func update(text: String, hint: GhostStyleHint = .completion, screenPoint: CGPoint) {
        if text.isEmpty {
            hide()
            return
        }
        viewModel.text = text
        viewModel.hint = hint
        let size = hostingController.view.fittingSize
        let width = max(160, min(560, size.width + 16))
        let height = max(20, size.height + 8)
        panel.setFrame(NSRect(x: screenPoint.x, y: screenPoint.y, width: width, height: height), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Double(Constants.Suggestion.ghostFadeInMs) / 1000.0
            panel.animator().alphaValue = 1.0
        }
    }

    func hide() {
        viewModel.text = ""
        panel.alphaValue = 0
        panel.orderOut(nil)
    }
}

enum GhostStyleHint: Sendable {
    case completion
    case snippet
    case spellingFix
    case grammarFix
}

@MainActor
final class GhostTextViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var hint: GhostStyleHint = .completion
}

struct GhostTextView: View {
    @ObservedObject var model: GhostTextViewModel

    var body: some View {
        // SF Pro at 14 pt blends with most app text (Mail, Notes, browsers,
        // Cursor, etc.) much better than monospace — the goal is to feel like
        // native predictive text, not a Terminal-style overlay.
        Text(model.text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, 1)
            .padding(.vertical, 0)
            .fixedSize(horizontal: true, vertical: true)
    }

    /// Color only — no pill background, no icon. The overlay reads as inline
    /// ghost text without obscuring what the user is actually typing.
    private var foreground: Color {
        switch model.hint {
        case .completion:  return QColors.ghostText
        case .snippet:     return QColors.accent.opacity(0.85)
        case .spellingFix, .grammarFix: return QColors.success.opacity(0.85)
        }
    }
}
