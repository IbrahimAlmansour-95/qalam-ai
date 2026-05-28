import SwiftUI

enum QModelCardStatus: Sendable {
    case notInstalled
    case downloading(progress: Double)
    case installed
    case active
}

struct QModelCard: View {
    let entry: ModelEntry
    let status: QModelCardStatus
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(entry.family.accent)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(QFonts.bodyMed)
                            .foregroundStyle(QColors.textPrimary)
                            .lineLimit(1)
                        if entry.recommended {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(QColors.warning)
                        }
                        Spacer(minLength: 0)
                        statusDot
                    }

                    HStack(spacing: 5) {
                        QTag(text: sizeText, style: .neutral)
                        QTag(text: entry.speed.label,
                             style: entry.speed == .fast ? .accent : .neutral,
                             icon: entry.speed.icon)
                        if entry.goodAtArabic {
                            QTag(text: "ع", style: .success)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
            .animation(QAnimation.quick, value: isSelected)
            .animation(QAnimation.quick, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var sizeText: String {
        String(format: "%.1f GB", entry.sizeGB)
    }

    private var statusDot: some View {
        Group {
            switch status {
            case .notInstalled:
                Circle().fill(QColors.textTertiary).frame(width: 8, height: 8)
            case .downloading:
                Circle().fill(QColors.accent).frame(width: 8, height: 8)
            case .installed:
                Circle().fill(QColors.success).frame(width: 8, height: 8)
            case .active:
                Circle().fill(QColors.success).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(QColors.success, lineWidth: 1).scaleEffect(1.8).opacity(0.4))
            }
        }
    }

    private var background: Color {
        if isSelected { return QColors.backgroundElevated }
        if isHovering { return Color.white.opacity(0.03) }
        return QColors.backgroundSecondary
    }

    private var borderColor: Color {
        if isSelected { return QColors.accent.opacity(0.5) }
        return QColors.borderSubtle
    }
}
