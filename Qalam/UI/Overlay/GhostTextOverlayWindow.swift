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

    /// `screenPoint` is the desired TOP-LEFT of the overlay in AppKit screen
    /// coords (bottom-left origin). We translate it to a bottom-left frame
    /// internally. The SwiftUI text uses topLeading alignment, so the text's
    /// top edge matches the caret line's top — visually inline with typing.
    func update(text: String, hint: GhostStyleHint = .completion, screenPoint: CGPoint) {
        if text.isEmpty {
            hide()
            return
        }
        viewModel.text = text
        viewModel.hint = hint
        let size = hostingController.view.fittingSize
        let width = max(40, min(560, ceil(size.width) + 2))
        let height = max(16, ceil(size.height))
        // NSWindow frames are bottom-left origin. screenPoint is top-left, so
        // subtract the height to get the bottom-left coordinate.
        panel.setFrame(NSRect(x: screenPoint.x,
                              y: screenPoint.y - height,
                              width: width,
                              height: height),
                       display: true)
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
        //
        // The frame(maxWidth/maxHeight) + alignment:.bottomLeading pins the
        // text to the bottom of the NSPanel content view so its baseline
        // sits at the caret baseline (the panel's bottom edge).
        Text(model.text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            // Top-leading: text's top edge sits at the panel's top, which is
            // anchored at the caret line's top. Combined with matching font
            // size (14 pt), this puts the ghost glyphs on the same baseline
            // as what the user is typing.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
