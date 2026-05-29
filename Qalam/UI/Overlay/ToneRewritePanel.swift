import Foundation
import AppKit
import SwiftUI

/// Small floating picker shown near the selection for tone-rewriting it.
@MainActor
final class ToneRewritePanel {
    static let shared = ToneRewritePanel()

    private let panel: NSPanel
    private let hosting: NSHostingController<ToneRewriteView>
    var isVisible: Bool { panel.isVisible }

    private init() {
        hosting = NSHostingController(rootView: ToneRewriteView())
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.contentViewController = hosting
        p.isMovableByWindowBackground = false
        panel = p
    }

    func show(near anchor: CGRect?) {
        let size = hosting.view.fittingSize
        let w = max(220, size.width)
        let h = max(56, size.height)
        let origin: CGPoint
        if let a = anchor {
            // Below the caret if there's room; coordinates are bottom-left.
            origin = CGPoint(x: a.minX, y: a.minY - h - 6)
        } else if let screen = NSScreen.main {
            origin = CGPoint(x: screen.frame.midX - w / 2, y: screen.frame.midY)
        } else {
            origin = CGPoint(x: 200, y: 200)
        }
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: w, height: h)), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

struct ToneRewriteView: View {
    @State private var rewriter = SelectionRewriter.shared
    @State private var l10n = LocalizationStore.shared

    var body: some View {
        ZStack {
            QVisualEffect(material: .popover)
            content
                .padding(QSpacing.s)
        }
        .frame(width: 260)
        .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                .strokeBorder(QColors.borderSubtle, lineWidth: 1)
        )
        .environment(\.layoutDirection, l10n.current.layoutDirection)
    }

    @ViewBuilder
    private var content: some View {
        switch rewriter.state {
        case .working(let tone):
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.6)
                Text("\(L.t(.rewriteWorking)) \(L.t(tone.localizationKey))…")
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t(.rewriteFailed))
                    .font(QFonts.caption).fontWeight(.semibold)
                    .foregroundStyle(QColors.destructive)
                Text(msg).font(QFonts.caption).foregroundStyle(QColors.textTertiary)
                    .lineLimit(2)
            }
        case .idle:
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(.rewriteTitle))
                    .font(QFonts.caption).fontWeight(.semibold)
                    .foregroundStyle(QColors.textTertiary)
                QFlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(RewriteTone.allCases) { tone in
                        toneButton(tone)
                    }
                }
            }
        }
    }

    private func toneButton(_ tone: RewriteTone) -> some View {
        Button {
            rewriter.apply(tone: tone)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tone.icon).font(.system(size: 10, weight: .semibold))
                Text(L.t(tone.localizationKey)).font(QFonts.caption).fontWeight(.medium)
            }
            .foregroundStyle(QColors.textPrimary)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(QColors.fillSubtle)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
