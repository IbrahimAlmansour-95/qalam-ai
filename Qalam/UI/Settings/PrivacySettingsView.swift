import SwiftUI

struct PrivacySettingsView: View {
    @State private var stats = UsageLogger.Snapshot(wordsCompletedToday: 0, keystrokesSaved: 0, suggestionsShown: 0)
    @State private var weekly: [(date: Date, words: Int)] = []
    @State private var styleEntries: Int = 0
    @State private var showResetConfirm = false
    @State private var showClearStyleConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.xl) {
                header
                pledgeCard
                compatibilityCard
                historyCard
                usageCard
            }
            .padding(QSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            Task {
                stats = await UsageLogger.shared.snapshot()
                weekly = await UsageLogger.shared.dailyHistory(days: 7)
                styleEntries = await StyleContextBuffer.shared.count()
            }
        }
    }

    private var compatibilityCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t(.popoverCompatibility))
                    .font(QFonts.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(QColors.textTertiary)

                row(icon: "checkmark.circle.fill",
                    tint: QColors.success,
                    text: L.t(.popoverCompatibilityWorks))
                row(icon: "switch.2",
                    tint: QColors.warning,
                    text: L.t(.popoverCompatibilityToggle))
                row(icon: "exclamationmark.triangle",
                    tint: QColors.destructive,
                    text: L.t(.popoverCompatibilityLimited))
            }
        }
    }

    private func row(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18, alignment: .center)
            Text(text)
                .font(QFonts.caption)
                .foregroundStyle(QColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var historyCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Last 7 days")
                        .font(QFonts.bodyMed)
                        .foregroundStyle(QColors.textPrimary)
                    Spacer()
                    let totalWeek = weekly.reduce(0) { $0 + $1.words }
                    Text("\(totalWeek) words")
                        .font(QFonts.mono)
                        .foregroundStyle(QColors.textSecondary)
                }
                WeeklyBarChart(data: weekly)
                    .frame(height: 110)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Privacy")
                .font(QFonts.display)
                .foregroundStyle(QColors.textPrimary)
            Text("All processing is local. Your text never leaves your Mac.")
                .font(QFonts.body)
                .foregroundStyle(QColors.textSecondary)
        }
    }

    private var pledgeCard: some View {
        QCard {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(QColors.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Local-first by design")
                        .font(QFonts.title)
                        .foregroundStyle(QColors.textPrimary)
                    Text("\(Constants.appName) runs a bundled Ollama engine on 127.0.0.1. There is no telemetry, no usage tracking, and no remote inference path.")
                        .font(QFonts.body)
                        .foregroundStyle(QColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var usageCard: some View {
        QCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Words completed today")
                        .font(QFonts.body)
                        .foregroundStyle(QColors.textSecondary)
                    Spacer()
                    Text("\(stats.wordsCompletedToday)")
                        .font(QFonts.mono)
                        .foregroundStyle(QColors.textPrimary)
                }

                QDivider()

                HStack {
                    Text("Style context entries")
                        .font(QFonts.body)
                        .foregroundStyle(QColors.textSecondary)
                    Spacer()
                    Text("\(styleEntries) entries")
                        .font(QFonts.mono)
                        .foregroundStyle(QColors.textPrimary)
                }

                QDivider()

                HStack(spacing: 10) {
                    QButton(title: "Clear Style History", icon: "trash",
                            style: .destructive, size: .medium) {
                        Task {
                            await StyleContextBuffer.shared.clear()
                            styleEntries = await StyleContextBuffer.shared.count()
                        }
                    }
                    QButton(title: "Reset Statistics", style: .ghost, size: .medium) {
                        Task {
                            await UsageLogger.shared.resetStatistics()
                            stats = await UsageLogger.shared.snapshot()
                        }
                    }
                    Spacer()
                }
            }
        }
    }

}
