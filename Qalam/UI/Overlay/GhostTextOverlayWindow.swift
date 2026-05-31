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
        viewModel.isRTL = isRTL
        // Show the ⇥/→ accept hint only for multi-char completions, when the
        // user has opted in. The glyph matches the configured accept key.
        viewModel.showHint = UserPreferences.shared.showAcceptHint
            && hint == .completion && text.count >= 2
        viewModel.hintGlyph = UserPreferences.shared.acceptWordKey == "rightArrow" ? "→" : "⇥"
        // The overlay panel occupies the EXACT caret line-box: its height is
        // the caret rect's height and its bottom sits on the caret's bottom.
        // The text inside fills that height and centers vertically, so its
        // baseline lands on the host line's baseline — reading as inline text
        // rather than a floating tooltip. We also scale the ghost font to the
        // line height when the host font size is unknown.
        let lineHeight = (caret.height >= 8 && caret.height < 200) ? caret.height : 0
        var style = style
        if lineHeight > 0 {
            // Size the ghost from the ACTUAL caret line box, not the AX-reported
            // font size. The two disagree whenever the text is rendered at a
            // different scale than its logical point size — large-font
            // documents, zoomed/presentation views, HiDPI quirks — and that
            // mismatch is what makes the ghost look like a tiny floating tag
            // instead of inline text. Line height ≈ point size × 1.3.
            let derived = lineHeight / 1.3
            // Trust the derived size when it diverges meaningfully from the
            // reported one (or when no font was detected); otherwise keep the
            // reported size which is already correct for normal text.
            if style.fontName == nil || abs(derived - style.pointSize) > 4 {
                style.pointSize = max(9, min(120, derived))
            }
        }
        // User calibration for apps that misreport caret geometry (e.g. Notes):
        // a size multiplier and a vertical nudge. Defaults (1.0, 0) are no-ops.
        let prefs = UserPreferences.shared
        let sizeScale = prefs.ghostSizeScale
        let vNudge = prefs.ghostVerticalOffset   // points; positive = move DOWN
        if sizeScale != 1.0 {
            style.pointSize = max(6, min(160, style.pointSize * sizeScale))
        }
        viewModel.style = style
        viewModel.lineHeight = lineHeight

        // Measure the ghost width DIRECTLY from the font. We can't use the
        // SwiftUI hosting view's fittingSize because the content uses
        // .frame(maxWidth: .infinity) for vertical centering, which collapses
        // the reported width to its minimum (~18px) and clipped long
        // suggestions to a sliver at the caret. NSAttributedString sizing is
        // exact and independent of layout.
        let measureFont: NSFont = {
            if let name = style.fontName, let f = NSFont(name: name, size: style.pointSize) {
                return f
            }
            return NSFont.systemFont(ofSize: style.pointSize)
        }()
        var measured = (text as NSString).size(withAttributes: [.font: measureFont]).width
        if viewModel.showHint {
            // Room for the "⇥" badge + spacing.
            measured += style.pointSize * 0.9 + 12
        }
        let width = max(8, min(900, ceil(measured) + 6))
        // Grow the panel to fit the (possibly scaled) text so it isn't clipped.
        let textLineHeight = ceil(measureFont.ascender - measureFont.descender + measureFont.leading)
        let height = max(lineHeight > 0 ? lineHeight : 16, textLineHeight)
        // Bottom-left origin: panel bottom == caret bottom, minus the user's
        // vertical nudge (positive nudge moves the ghost down = lower cocoa y).
        let y = caret.minY - vNudge
        let x = isRTL ? (caret.minX - 1 - width) : (caret.maxX + 1)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        // Show instantly — a fade reads as a popover/hover. Inline text just
        // appears.
        panel.alphaValue = 1.0
        if !panel.isVisible {
            panel.orderFrontRegardless()
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
    /// The host line-box height; when > 0 the text is vertically centered in
    /// it so the baseline matches the surrounding text.
    @Published var lineHeight: CGFloat = 0
    /// Show a faint key hint (e.g. ⇥) after the ghost text.
    @Published var showHint: Bool = false
    @Published var hintGlyph: String = "⇥"
}

struct GhostTextView: View {
    @ObservedObject var model: GhostTextViewModel

    var body: some View {
        // Render in the HOST field's own font, size, and color (at reduced
        // opacity) so the suggestion blends into the line like macOS's native
        // QuickType, instead of a fixed overlay font that reads as separate.
        // Vertically centered inside the caret line-box → shared baseline.
        HStack(spacing: 4) {
            Text(model.text)
                .font(hostFont)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
            if model.showHint {
                Text(model.hintGlyph)
                    .font(.system(size: max(9, model.style.pointSize * 0.7), weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .padding(.horizontal, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .fixedSize()
            }
        }
        // Bottom-align (not center) so the ghost sits on the host text's
        // BASELINE — host glyphs rest near the bottom of the caret line-box, so
        // centering left the ghost a few px high ("near cursor but off").
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: model.isRTL ? .bottomTrailing : .bottomLeading)
        .environment(\.layoutDirection, model.isRTL ? .rightToLeft : .leftToRight)
    }

    private var hostFont: Font {
        let size = model.style.pointSize
        if let name = model.style.fontName, !name.isEmpty {
            return Font.custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .regular)
    }

    /// EVERY ghost — completion, snippet, or correction — renders as a dimmed
    /// version of the user's OWN text color so it reads as an inline
    /// continuation of the line, exactly like Cotypist / macOS QuickType.
    /// We deliberately do NOT use branded accent/amber/green colors: those read
    /// as a floating tag above the text instead of inline ghost text, which is
    /// exactly the "yellow ghost above the line" the user disliked.
    private var foreground: Color {
        if let c = model.style.rgba, c.count == 4 {
            return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: 0.5)
        }
        // Host color unknown — neutral gray that reads as faded text in both
        // light and dark.
        return Color.secondary.opacity(0.9)
    }
}
