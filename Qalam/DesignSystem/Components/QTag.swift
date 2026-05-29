import SwiftUI

enum QTagStyle {
    case neutral
    case accent
    case success
    case warning
    case destructive

    var foreground: Color {
        switch self {
        case .neutral:     return QColors.textSecondary
        case .accent:      return QColors.accent
        case .success:     return QColors.success
        case .warning:     return QColors.warning
        case .destructive: return QColors.destructive
        }
    }

    var background: Color {
        switch self {
        case .neutral:     return QColors.fillSubtle
        case .accent:      return QColors.accent.opacity(0.15)
        case .success:     return QColors.success.opacity(0.15)
        case .warning:     return QColors.warning.opacity(0.15)
        case .destructive: return QColors.destructive.opacity(0.15)
        }
    }
}

struct QTag: View {
    let text: String
    var style: QTagStyle = .neutral
    var showDot: Bool = false
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if showDot {
                Circle()
                    .fill(style.foreground)
                    .frame(width: 6, height: 6)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(QFonts.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(style.foreground)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(style.background)
        .clipShape(Capsule())
        // Chips size to their content and never wrap or compress.
        .fixedSize(horizontal: true, vertical: false)
    }
}
