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
    func update(text: String,
                hint: GhostStyleHint = .completion,
                style: AccessibilityMonitor.CaretStyle,
                screenPoint: CGPoint) {
        if text.isEmpty {
            hide()
            return
        }
        viewModel.text = text
        viewModel.hint = hint
        viewModel.style = style
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
    @Published var style: AccessibilityMonitor.CaretStyle =
        .init(fontName: nil, pointSize: 14, rgba: nil)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case .snippet:
            return QColors.accent.opacity(0.85)
        case .spellingFix, .grammarFix:
            return QColors.success.opacity(0.85)
        case .completion:
            if let c = model.style.rgba, c.count == 4 {
                return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: 0.45)
            }
            return QColors.ghostText
        }
    }
}
