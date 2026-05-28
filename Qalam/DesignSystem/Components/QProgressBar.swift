import SwiftUI

struct QProgressBar: View {
    var progress: Double  // 0.0 ... 1.0
    var height: CGFloat = 6
    var tint: Color = QColors.accent
    var showShine: Bool = true

    @State private var shinePhase: Double = -1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(tint)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
                    .animation(QAnimation.standard, value: progress)

                if showShine && progress > 0 && progress < 1 {
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.35), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 60)
                        .offset(x: shinePhase * geo.size.width)
                        .mask(
                            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                                .frame(width: max(0, min(1, progress)) * geo.size.width)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )
                        .onAppear {
                            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                                shinePhase = 1.2
                            }
                        }
                }
            }
        }
        .frame(height: height)
    }
}
