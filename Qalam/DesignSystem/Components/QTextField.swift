import SwiftUI

struct QTextField: View {
    var placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textTertiary)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(QFonts.body)
                .foregroundStyle(QColors.textPrimary)
                .focused($focused)
                .onSubmit { onSubmit?() }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(QColors.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous)
                .strokeBorder(focused ? QColors.accent.opacity(0.6) : QColors.borderMedium,
                              lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QRadius.medium, style: .continuous))
        .animation(QAnimation.quick, value: focused)
    }
}
