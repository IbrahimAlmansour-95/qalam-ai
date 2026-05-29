import SwiftUI

enum QButtonStyle {
    case primary
    case secondary
    case ghost
    case destructive
}

enum QButtonSize {
    case small
    case medium
    case large

    var verticalPadding: CGFloat {
        switch self {
        case .small:  return 6
        case .medium: return 9
        case .large:  return 12
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small:  return 10
        case .medium: return 14
        case .large:  return 18
        }
    }

    var font: Font {
        switch self {
        case .small:  return QFonts.caption
        case .medium: return QFonts.bodyMed
        case .large:  return QFonts.bodyMed
        }
    }
}

struct QButton: View {
    let title: String
    var icon: String? = nil
    var style: QButtonStyle = .primary
    var size: QButtonSize = .medium
    var fullWidth: Bool = false
    var disabled: Bool = false
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: { if !disabled { action() } }) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(size.font)
                }
                Text(title)
                    .font(size.font)
            }
            .padding(.vertical, size.verticalPadding)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
            .opacity(disabled ? 0.4 : 1.0)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(QAnimation.quick, value: isHovering)
            .animation(QAnimation.quick, value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            isHovering = hovering
            if hovering && !disabled {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !disabled { isPressed = true } }
                .onEnded   { _ in isPressed = false }
        )
    }

    private var foreground: Color {
        switch style {
        case .primary:     return .white
        case .secondary:   return QColors.textPrimary
        case .ghost:       return QColors.textSecondary
        case .destructive: return QColors.destructive
        }
    }

    private var background: some View {
        Group {
            switch style {
            case .primary:
                (isHovering ? QColors.accentHover : QColors.accent)
            case .secondary:
                (isHovering ? QColors.backgroundElevated : QColors.backgroundSecondary)
            case .ghost:
                (isHovering ? QColors.fillSubtle : Color.clear)
            case .destructive:
                QColors.destructive.opacity(isHovering ? 0.18 : 0.10)
            }
        }
    }

    private var border: Color {
        switch style {
        case .primary:     return Color.white.opacity(0.08)
        case .secondary:   return QColors.borderMedium
        case .ghost:       return .clear
        case .destructive: return QColors.destructive.opacity(0.35)
        }
    }
}
