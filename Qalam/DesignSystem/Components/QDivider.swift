import SwiftUI

struct QDivider: View {
    var orientation: Axis = .horizontal

    var body: some View {
        Group {
            if orientation == .horizontal {
                Rectangle().fill(QColors.borderSubtle).frame(height: 1)
            } else {
                Rectangle().fill(QColors.borderSubtle).frame(width: 1)
            }
        }
    }
}
