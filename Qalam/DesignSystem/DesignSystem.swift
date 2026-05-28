import SwiftUI
import AppKit

enum QColors {
    static let backgroundPrimary   = Color(red: 18/255,  green: 18/255,  blue: 20/255)
    static let backgroundSecondary = Color(red: 26/255,  green: 26/255,  blue: 30/255)
    static let backgroundElevated  = Color(red: 34/255,  green: 34/255,  blue: 40/255)

    static let borderSubtle = Color.white.opacity(0.07)
    static let borderMedium = Color.white.opacity(0.12)

    static let accent      = Color(red: 99/255,  green: 102/255, blue: 241/255)
    static let accentHover = Color(red: 118/255, green: 120/255, blue: 252/255)

    static let textPrimary   = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.52)
    static let textTertiary  = Color.white.opacity(0.30)

    static let ghostText = Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.45)

    static let success     = Color(red: 52/255,  green: 211/255, blue: 153/255)
    static let warning     = Color(red: 251/255, green: 191/255, blue: 36/255)
    static let destructive = Color(red: 239/255, green: 68/255,  blue: 68/255)

    // Family accents for QModelCard left borders
    static let familyGemma  = Color(red: 59/255,  green: 130/255, blue: 246/255) // blue
    static let familyQwen   = Color(red: 168/255, green: 85/255,  blue: 247/255) // purple
    static let familyPhi    = Color(red: 249/255, green: 115/255, blue: 22/255)  // orange
    static let familyLlama  = Color(red: 34/255,  green: 197/255, blue: 94/255)  // green
    static let familySmol   = Color(red: 20/255,  green: 184/255, blue: 166/255) // teal
    static let familyOther  = Color.white.opacity(0.4)
}

enum QFonts {
    // `tracking` belongs on Text/View, not Font; track-tuned variants are
    // applied at call sites where it matters.
    static let display = Font.system(size: 28, weight: .semibold)
    static let title   = Font.system(size: 18, weight: .semibold)
    static let body    = Font.system(size: 13, weight: .regular)
    static let bodyMed = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11, weight: .regular)
    static let mono    = Font.system(size: 12, weight: .regular, design: .monospaced)
}

enum QSpacing {
    static let xs: CGFloat = 4
    static let s:  CGFloat = 8
    static let m:  CGFloat = 12
    static let l:  CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum QRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
    static let xlarge: CGFloat = 20
}

enum QAnimation {
    static let quick   = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let spring  = Animation.spring(response: 0.35, dampingFraction: 0.75)
}

// MARK: - Visual effect background helper

struct QVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

// MARK: - View modifiers

struct QCardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.30), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.20), radius: 2, x: 0, y: 1)
    }
}

struct QPopoverShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.50), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.30), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func qCardShadow() -> some View { modifier(QCardShadow()) }
    func qPopoverShadow() -> some View { modifier(QPopoverShadow()) }
}
