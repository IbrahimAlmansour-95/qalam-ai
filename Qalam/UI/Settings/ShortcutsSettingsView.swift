import SwiftUI

/// Every shortcut QalamAI handles, with what it does and (for the global
/// ones) a switch to turn it off. Key labels name physical keys, so they read
/// the same on any keyboard layout.
struct ShortcutsSettingsView: View {
    @State private var prefs = UserPreferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                card(title: L.t(.shortcutCardVisible), rows: rows(in: .suggestion))
                anywhereCard
                escCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rows(in section: ShortcutSection) -> [ShortcutInfo] {
        ShortcutCatalog.all.filter { $0.section == section }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(.shortcutsHeading))
                .font(QFonts.display)
                .foregroundStyle(QColors.textPrimary)
            Text(L.t(.shortcutsSubheading))
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Cards

    private func card(title: String, rows: [ShortcutInfo]) -> some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(title)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, info in
                    if index > 0 { QDivider() }
                    shortcutRow(info)
                }
            }
        }
    }

    private var anywhereCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(L.t(.shortcutCardAnywhere))
                ForEach(Array(rows(in: .anywhere).enumerated()), id: \.element.id) { index, info in
                    if index > 0 { QDivider() }
                    shortcutRow(info)
                }
                QDivider()
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11))
                        .foregroundStyle(QColors.textTertiary)
                    Text(L.t(.shortcutKeyAboveTabHelp))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var escCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L.t(.shortcutCardEsc))
                VStack(spacing: 6) {
                    escOption(L.t(.shortcutEscDismiss), value: .dismissOnly)
                    escOption(L.t(.shortcutEscDismissPause), value: .dismissAndPause)
                    escOption(L.t(.shortcutEscPass), value: .passThrough)
                }
                Text(L.t(.shortcutEscHelp))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func escOption(_ title: String, value: EscBehavior) -> some View {
        let active = prefs.escBehavior == value
        return Button {
            withAnimation(QAnimation.quick) { prefs.escBehavior = value }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: active ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(active ? QColors.accent : QColors.textTertiary)
                Text(title)
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows

    private func shortcutRow(_ info: ShortcutInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t(info.title))
                    .font(QFonts.bodyMed)
                    .foregroundStyle(QColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L.t(info.help))
                    .font(QFonts.caption)
                    .foregroundStyle(QColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(info.notes, id: \.self) { note in
                    Text(L.t(note))
                        .font(QFonts.caption)
                        .foregroundStyle(QColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            // Shortcut notation reads left-to-right in both UI languages.
            HStack(spacing: 4) {
                ForEach(Array(info.keys.enumerated()), id: \.offset) { _, key in
                    keyChip(key)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            if let isEnabled = info.isEnabled, let setEnabled = info.setEnabled {
                QToggle(isOn: Binding(get: { isEnabled() }, set: { setEnabled($0) }))
                    .fixedSize()
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(QFonts.caption)
            .fontWeight(.semibold)
            .foregroundStyle(QColors.textTertiary)
    }

    private func keyChip(_ key: String) -> some View {
        Text(key)
            .font(QFonts.mono)
            .foregroundStyle(QColors.textPrimary)
            .lineLimit(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(QColors.backgroundElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(QColors.borderMedium, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
