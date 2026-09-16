import Foundation
import AppKit
import SwiftUI

/// Fallback surface for the suggestion: a compact bubble anchored to the
/// focused FIELD instead of the caret.
///
/// It is used only where inline ghost text can't be placed — `caretFrame()`
/// returns nothing (Electron canvas editors, some web editors) — or when the
/// user picked "Mirror bubble" for an app or site. Inline placement is never
/// replaced while the caret is readable.
///
/// Click-through and non-activating like the ghost panel, so it never takes a
/// click or the keyboard focus; accept / dismiss keys act on the suggestion
/// exactly as they do inline.
@MainActor
final class MirrorBubblePanel {
    static let shared = MirrorBubblePanel()

    private let panel: NSPanel
    private let hosting: NSHostingController<MirrorBubbleView>
    private let model: MirrorBubbleModel

    /// Bubble is on screen with text in it.
    var isVisible: Bool { panel.isVisible && !model.text.isEmpty }
    /// Current screen frame (used by the field button's overlap check).
    var frame: NSRect { panel.frame }

    // Layout constants, shared with the SwiftUI view so measuring and drawing
    // agree (same approach as the ghost window and the status toast).
    nonisolated fileprivate static let horizontalPadding: CGFloat = 10
    nonisolated fileprivate static let verticalPadding: CGFloat = 6
    nonisolated fileprivate static let cornerRadius: CGFloat = 8
    nonisolated fileprivate static let iconWidth: CGFloat = 13
    nonisolated fileprivate static let spacing: CGFloat = 6
    private static let fontSize: CGFloat = 13
    private static let hintWidth: CGFloat = 20
    private static let maxWidth: CGFloat = 520
    private static let minWidth: CGFloat = 160
    /// Fields taller than this are treated as editors: the bubble sits just
    /// inside their top edge instead of floating above the whole document.
    private static let largeFieldHeight: CGFloat = 160
    private static let fieldGap: CGFloat = 6

    private init() {
        let m = MirrorBubbleModel()
        model = m
        hosting = NSHostingController(rootView: MirrorBubbleView(model: m))
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.contentViewController = hosting
        p.alphaValue = 0
        panel = p
    }

    /// Shows `text` anchored to `fieldFrame` (AppKit screen coordinates,
    /// bottom-left origin — the same space `focusedFrame()` returns).
    func show(text: String, hint: GhostStyleHint, fieldFrame: CGRect, isRTL: Bool) {
        guard !text.isEmpty else {
            hide()
            return
        }
        let prefs = UserPreferences.shared
        let isCorrection = hint == .spellingFix || hint == .grammarFix
        let showHint = prefs.showAcceptHint && hint == .completion && text.count >= 2

        model.text = text
        model.isRTL = isRTL
        model.showCorrectionIcon = isCorrection
        model.showHint = showHint
        model.hintGlyph = prefs.acceptWordKey == "rightArrow" ? "→" : "⇥"

        let size = Self.measure(text: text, fieldWidth: fieldFrame.width,
                                showIcon: isCorrection, showHint: showHint)
        let origin = Self.origin(for: size, fieldFrame: fieldFrame, isRTL: isRTL)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        guard panel.isVisible || !model.text.isEmpty else { return }
        model.text = ""
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    // MARK: - Geometry

    /// Measured from the font directly (the hosting view's fitting size still
    /// describes the previous suggestion at this point).
    private static func measure(text: String, fieldWidth: CGFloat,
                                showIcon: Bool, showHint: Bool) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        var chrome = horizontalPadding * 2
        if showIcon { chrome += iconWidth + spacing }
        if showHint { chrome += hintWidth + spacing }
        let maxTotal = min(maxWidth, max(minWidth, fieldWidth))
        let textLimit = max(60, maxTotal - chrome)
        let box = (text as NSString).boundingRect(
            with: CGSize(width: textLimit, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        // The view clips to two lines; don't reserve height for more.
        let textHeight = min(ceil(box.height), lineHeight * 2)
        return CGSize(width: min(maxTotal, max(120, ceil(box.width) + chrome + 2)),
                      height: max(24, textHeight + verticalPadding * 2))
    }

    private static func origin(for size: CGSize, fieldFrame: CGRect, isRTL: Bool) -> CGPoint {
        let screen = screenFor(fieldFrame)
        let visible = screen?.visibleFrame ?? fieldFrame

        var x = isRTL ? (fieldFrame.maxX - size.width) : fieldFrame.minX
        x = min(max(x, visible.minX + 2), max(visible.minX + 2, visible.maxX - size.width - 2))

        var y: CGFloat
        if fieldFrame.height > largeFieldHeight {
            // Large editor: inside its top edge, so the bubble stays over the
            // text being written instead of floating far above it.
            y = fieldFrame.maxY - size.height - 8
        } else {
            y = fieldFrame.maxY + fieldGap
            if y + size.height > visible.maxY {
                y = fieldFrame.minY - fieldGap - size.height
            }
        }
        y = min(max(y, visible.minY + 2), max(visible.minY + 2, visible.maxY - size.height - 2))
        return CGPoint(x: x, y: y)
    }

    /// The screen showing most of the field (multi-monitor), else the main one.
    private static func screenFor(_ rect: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(rect)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best ?? NSScreen.main
    }
}

@MainActor
final class MirrorBubbleModel: ObservableObject {
    @Published var text: String = ""
    @Published var isRTL: Bool = false
    @Published var showCorrectionIcon: Bool = false
    @Published var showHint: Bool = false
    @Published var hintGlyph: String = "⇥"
}

struct MirrorBubbleView: View {
    @ObservedObject var model: MirrorBubbleModel

    var body: some View {
        HStack(spacing: MirrorBubblePanel.spacing) {
            if model.showCorrectionIcon {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(QColors.accent)
                    .frame(width: MirrorBubblePanel.iconWidth)
            }
            Text(model.text)
                .font(QFonts.body)
                // Dimmed like the inline ghost, but readable on the bubble's
                // material in both light and dark.
                .foregroundStyle(QColors.textPrimary.opacity(0.75))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if model.showHint {
                Text(model.hintGlyph)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(QColors.textTertiary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(QColors.fillSubtle)
                    )
                    .fixedSize()
            }
        }
        .padding(.horizontal, MirrorBubblePanel.horizontalPadding)
        .padding(.vertical, MirrorBubblePanel.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: model.isRTL ? .trailing : .leading)
        .background(QVisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: MirrorBubblePanel.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MirrorBubblePanel.cornerRadius, style: .continuous)
                .strokeBorder(QColors.borderSubtle, lineWidth: 1)
        )
        .environment(\.layoutDirection, model.isRTL ? .rightToLeft : .leftToRight)
    }
}
