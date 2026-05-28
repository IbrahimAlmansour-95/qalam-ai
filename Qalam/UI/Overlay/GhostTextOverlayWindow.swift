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

    /// `caret` is the validated caret rect in AppKit screen coords (bottom-left
    /// origin). For LTR the overlay extends rightward from the caret's right
    /// edge; for RTL (Arabic) it extends leftward from the caret's left edge,
    /// so the ghost reads inline on the line the user is typing in either
    /// direction.
    func update(text: String,
                hint: GhostStyleHint = .completion,
                style: AccessibilityMonitor.CaretStyle,
                caret: CGRect,
                isRTL: Bool) {
        if text.isEmpty {
            hide()
            return
        }
        viewModel.text = text
        viewModel.hint = hint
        viewModel.style = style
        viewModel.isRTL = isRTL
        let size = hostingController.view.fittingSize
        let width = max(40, min(560, ceil(size.width) + 2))
        let height = max(16, ceil(size.height))
        // Top of the caret line. NSWindow frames are bottom-left origin, so
        // the panel's y is (lineTop - height).
        let topY = caret.maxY
        let x = isRTL ? (caret.minX - 1 - width) : (caret.maxX + 1)
        panel.setFrame(NSRect(x: x,
                              y: topY - height,
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
    @Published var style: AccessibilityMonitor.CaretStyle =
        .init(fontName: nil, pointSize: 14, rgba: nil)
    @Published var isRTL: Bool = false
}

struct GhostTextView: View {
    @ObservedObject var model: GhostTextViewModel

    var body: some View {
        // Render in the HOST field's own font, size, and color (at reduced
        // opacity) so the suggestion blends into the line like macOS's native
        // QuickType, instead of a fixed overlay font that reads as separate.
        Text(model.text)
            .font(hostFont)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: model.isRTL ? .topTrailing : .topLeading)
            .environment(\.layoutDirection, model.isRTL ? .rightToLeft : .leftToRight)
    }

    private var hostFont: Font {
        let size = model.style.pointSize
        if let name = model.style.fontName, !name.isEmpty {
            return Font.custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .regular)
    }

    /// Use the host text color for completions (the most "inline" look), the
    /// accent for snippet/emoji, success-green for corrections — all dimmed so
    /// the ghost is clearly provisional.
    private var foreground: Color {
        switch model.hint {
        case .completion:
            // Inline autocomplete: a dimmed version of the user's OWN text
            // color so it reads as a continuation of the same line — exactly
            // like macOS QuickType. Never accent/green.
            if let c = model.style.rgba, c.count == 4 {
                return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: 0.5)
            }
            // Host color unknown — neutral gray that reads as faded text in
            // both light and dark, not a branded color.
            return Color.secondary.opacity(0.9)
        case .snippet:
            // Snippets/emoji are an explicit insertion, so a subtle accent is OK.
            return QColors.accent.opacity(0.8)
        case .spellingFix, .grammarFix:
            // Corrections are deliberately distinct (they replace text), but
            // muted so they don't shout.
            return QColors.warning.opacity(0.9)
        }
    }
}
