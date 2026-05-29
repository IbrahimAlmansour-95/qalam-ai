import SwiftUI

struct QToggle: View {
    @Binding var isOn: Bool
    var label: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let label {
                Text(label)
                    .font(QFonts.body)
                    .foregroundStyle(QColors.textPrimary)
            }
            Spacer(minLength: 0)
            switchTrack
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(QAnimation.spring) {
                isOn.toggle()
            }
        }
    }

    private var switchTrack: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? QColors.accent : QColors.fillMedium)
                .frame(width: 36, height: 20)
            Circle()
                .fill(.white)
                .frame(width: 16, height: 16)
                .padding(2)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
        }
        .animation(QAnimation.spring, value: isOn)
    }
}
