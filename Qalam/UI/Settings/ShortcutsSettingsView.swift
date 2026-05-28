import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                fixedShortcutsCard
                customShortcutsCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t(.shortcutsHeading))
                .font(QFonts.display)
                .foregroundStyle(QColors.textPrimary)
            Text(L.t(.shortcutsSubheading))
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
        }
    }

    private var fixedShortcutsCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 14) {
                shortcutRow(label: L.t(.shortcutAcceptWord), keys: ["Tab"])
                QDivider()
                shortcutRow(label: L.t(.shortcutAcceptLine), keys: ["⇧", "Tab"])
                QDivider()
                shortcutRow(label: L.t(.shortcutDismiss), keys: ["Esc"])
                QDivider()
                shortcutRow(label: "Open settings", keys: ["⌘", ","])
            }
        }
    }

    private var customShortcutsCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t(.shortcutPauseResume))
                            .font(QFonts.bodyMed)
                            .foregroundStyle(QColors.textPrimary)
                        Text(L.t(.shortcutPauseHelp))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textTertiary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        keyChip("⌘")
                        keyChip("⇧")
                        keyChip("Space")
                    }
                }
            }
        }
    }

    private func shortcutRow(label: String, keys: [String]) -> some View {
        HStack {
            Text(label)
                .font(QFonts.body)
                .foregroundStyle(QColors.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    keyChip(key)
                }
            }
        }
    }

    private func keyChip(_ key: String) -> some View {
        Text(key)
            .font(QFonts.mono)
            .foregroundStyle(QColors.textPrimary)
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
