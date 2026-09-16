import Foundation
import AppKit
import SwiftUI

/// The numbered list of other words that could come next (⌥\, or after a
/// pause when the user asks for that).
///
/// Like every other QalamAI surface it is click-through and non-activating —
/// the app being typed in keeps the keyboard, and `KeystrokeInterceptor`
/// turns 1…5 / Esc into list actions only while this panel is up. The inline
/// ghost and the mirror bubble are hidden while it shows, so exactly one
/// suggestion surface is ever on screen.
@MainActor
final class AlternativesPanel {
    static let shared = AlternativesPanel()

    /// Where the list hangs from: the caret when we have one, otherwise the
    /// mirror bubble or the focused field.
    struct Anchor: Equatable, Sendable {
        let rect: CGRect
        let isRTL: Bool
        /// A tall rect is a whole editor, not a line: hang the list from its
        /// TOP edge rather than from the bottom of the document.
        var isLarge: Bool { rect.height > AlternativesPanel.largeAnchorHeight }
    }

    /// Cheap enough to read from the keystroke tap (a stored Bool, no AppKit).
    private(set) var isVisible = false
    /// Current screen frame (used by the field button's overlap check).
    var frame: NSRect { panel.frame }

    private let panel: NSPanel
    private let hosting: NSHostingController<AlternativesListView>
    private let model: AlternativesListModel

    // Layout constants, shared with the SwiftUI view so measuring and drawing
    // agree (same approach as the ghost window and the mirror bubble).
    nonisolated fileprivate static let horizontalPadding: CGFloat = 10
    nonisolated fileprivate static let verticalPadding: CGFloat = 7
    nonisolated fileprivate static let cornerRadius: CGFloat = 8
    nonisolated fileprivate static let rowSpacing: CGFloat = 3
    nonisolated fileprivate static let chipWidth: CGFloat = 16
    nonisolated fileprivate static let chipSpacing: CGFloat = 8
    nonisolated fileprivate static let rowHeight: CGFloat = 19
    private static let fontSize: CGFloat = 13
    private static let maxWidth: CGFloat = 320
    private static let minWidth: CGFloat = 150
    /// `Anchor` is a plain value type, so this has to be reachable off the
    /// main actor.
    nonisolated fileprivate static let largeAnchorHeight: CGFloat = 120
    private static let anchorGap: CGFloat = 4

    private init() {
        let m = AlternativesListModel()
        model = m
        hosting = NSHostingController(rootView: AlternativesListView(model: m))
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
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

    /// Shows (or updates) the list. `loading` with no options yet draws a
    /// single "looking for alternatives" row so the shortcut feels immediate.
    func show(options: [String], loading: Bool, anchor: Anchor) {
        guard loading || !options.isEmpty else {
            hide()
            return
        }
        model.options = options
        model.isLoading = loading && options.isEmpty
        model.loadingText = L.t(.alternativesLoading)
        model.isRTL = anchor.isRTL

        let size = Self.measure(options: options, loading: model.isLoading,
                                loadingText: model.loadingText)
        let origin = Self.origin(for: size, anchor: anchor)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        isVisible = true
    }

    func hide() {
        guard isVisible || panel.isVisible else { return }
        isVisible = false
        model.options = []
        model.isLoading = false
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    // MARK: - Geometry

    /// Measured from the font directly — the hosting view's fitting size still
    /// describes the previous list at this point.
    private static func measure(options: [String], loading: Bool, loadingText: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        let chrome = horizontalPadding * 2 + chipWidth + chipSpacing
        let rows = loading ? [loadingText] : options
        var widest: CGFloat = 0
        for row in rows {
            let box = (row as NSString).size(withAttributes: [.font: font])
            widest = max(widest, ceil(box.width))
        }
        let width = min(maxWidth, max(minWidth, widest + chrome + 2))
        let count = max(1, rows.count)
        let height = CGFloat(count) * rowHeight
            + CGFloat(count - 1) * rowSpacing
            + verticalPadding * 2
        return CGSize(width: width, height: ceil(height))
    }

    private static func origin(for size: CGSize, anchor: Anchor) -> CGPoint {
        let rect = anchor.rect
        let visible = screenFor(rect)?.visibleFrame ?? rect

        var x = anchor.isRTL ? (rect.maxX - size.width) : rect.minX
        x = min(max(x, visible.minX + 2), max(visible.minX + 2, visible.maxX - size.width - 2))

        // Below the caret line (or the top edge of a large field); if it
        // doesn't fit there, flip above.
        let top = anchor.isLarge ? rect.maxY : rect.minY
        var y = top - size.height - anchorGap
        if y < visible.minY + 2 {
            y = rect.maxY + anchorGap
        }
        y = min(max(y, visible.minY + 2), max(visible.minY + 2, visible.maxY - size.height - 2))
        return CGPoint(x: x, y: y)
    }

    /// The screen showing most of the anchor (multi-monitor), else the main one.
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
final class AlternativesListModel: ObservableObject {
    @Published var options: [String] = []
    @Published var isLoading = false
    @Published var loadingText = ""
    @Published var isRTL = false
}

struct AlternativesListView: View {
    @ObservedObject var model: AlternativesListModel

    var body: some View {
        VStack(alignment: .leading, spacing: AlternativesPanel.rowSpacing) {
            if model.isLoading {
                HStack(spacing: AlternativesPanel.chipSpacing) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: AlternativesPanel.chipWidth)
                    Text(model.loadingText)
                        .font(QFonts.body)
                        .foregroundStyle(QColors.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: AlternativesPanel.rowHeight)
            } else {
                ForEach(Array(model.options.enumerated()), id: \.offset) { index, option in
                    row(number: index + 1, text: option)
                }
            }
        }
        .padding(.horizontal, AlternativesPanel.horizontalPadding)
        .padding(.vertical, AlternativesPanel.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(QVisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: AlternativesPanel.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AlternativesPanel.cornerRadius, style: .continuous)
                .strokeBorder(QColors.borderSubtle, lineWidth: 1)
        )
        .environment(\.layoutDirection, model.isRTL ? .rightToLeft : .leftToRight)
    }

    private func row(number: Int, text: String) -> some View {
        HStack(spacing: AlternativesPanel.chipSpacing) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(QColors.textTertiary)
                .frame(width: AlternativesPanel.chipWidth)
                // The digit names a key, so it reads left-to-right either way.
                .environment(\.layoutDirection, .leftToRight)
            Text(text)
                .font(QFonts.body)
                .foregroundStyle(QColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: AlternativesPanel.rowHeight)
    }
}
