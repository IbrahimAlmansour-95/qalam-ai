import SwiftUI

struct WeeklyBarChart: View {
    let data: [(date: Date, words: Int)]

    private var maxValue: Int {
        max(1, data.map(\.words).max() ?? 1)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        let height = max(2, CGFloat(point.words) / CGFloat(maxValue) * (geo.size.height - 26))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [QColors.accent.opacity(0.85),
                                             QColors.accent.opacity(0.55)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: height)
                            .overlay(
                                Text("\(point.words)")
                                    .font(QFonts.caption)
                                    .foregroundStyle(QColors.textPrimary)
                                    .padding(.bottom, 2)
                                    .opacity(point.words > 0 ? 1 : 0),
                                alignment: .top
                            )
                        Text(WeeklyBarChart.dayLabel(point.date))
                            .font(QFonts.caption)
                            .foregroundStyle(QColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }
}
