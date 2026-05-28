import SwiftUI

struct QCard<Content: View>: View {
    var padding: CGFloat = QSpacing.l
    var elevated: Bool = false
    var accentBorder: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(elevated ? QColors.backgroundElevated : QColors.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: QRadius.large, style: .continuous)
                    .strokeBorder(accentBorder ?? QColors.borderSubtle,
                                  lineWidth: accentBorder != nil ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: QRadius.large, style: .continuous))
            .qCardShadow()
    }
}
