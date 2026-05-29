import SwiftUI
import AppKit

enum QColors {
    /// A dynamic color that resolves per the drawing view's effective
    /// appearance, so the whole UI follows the chosen Light / Dark / System
    /// theme (set globally via `NSApp.appearance` in AppearanceManager).
    /// `light` / `dark` are sRGB (red, green, blue, alpha) in 0…1.
    private static func dyn(light: (CGFloat, CGFloat, CGFloat, CGFloat),
                            dark:  (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }

    private static func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    static let backgroundPrimary   = dyn(light: (250/255, 250/255, 252/255, 1),
                                          dark:  (18/255,  18/255,  20/255,  1))
    static let backgroundSecondary = dyn(light: (242/255, 242/255, 246/255, 1),
                                          dark:  (26/255,  26/255,  30/255,  1))
    static let backgroundElevated  = dyn(light: (255/255, 255/255, 255/255, 1),
                                          dark:  (34/255,  34/255,  40/255,  1))

    static let borderSubtle = dyn(light: (0, 0, 0, 0.08), dark: (1, 1, 1, 0.07))
    static let borderMedium = dyn(light: (0, 0, 0, 0.14), dark: (1, 1, 1, 0.12))

    static let accent      = solid(99, 102, 241)
    static let accentHover = solid(118, 120, 252)

    static let textPrimary   = dyn(light: (0, 0, 0, 0.88), dark: (1, 1, 1, 0.92))
    static let textSecondary = dyn(light: (0, 0, 0, 0.55), dark: (1, 1, 1, 0.52))
    static let textTertiary  = dyn(light: (0, 0, 0, 0.38), dark: (1, 1, 1, 0.30))

    static let ghostText = solid(99, 102, 241, 0.45)

    static let success     = solid(52, 211, 153)
    static let warning     = solid(251, 191, 36)
    static let destructive = solid(239, 68, 68)

    // Family accents for QModelCard left borders
    static let familyGemma  = solid(59, 130, 246)  // blue
    static let familyQwen   = solid(168, 85, 247)  // purple
    static let familyPhi    = solid(249, 115, 22)  // orange
    static let familyLlama  = solid(34, 197, 94)   // green
    static let familySmol   = solid(20, 184, 166)  // teal
    static let familyOther  = dyn(light: (0, 0, 0, 0.4), dark: (1, 1, 1, 0.4))

    // Adaptive neutral fills for chips, control tracks, and hover states —
    // a faint dark wash in light mode, a faint light wash in dark mode.
    static let fillSubtle = dyn(light: (0, 0, 0, 0.05), dark: (1, 1, 1, 0.06))
    static let fillMedium = dyn(light: (0, 0, 0, 0.10), dark: (1, 1, 1, 0.12))
    static let fillFaint  = dyn(light: (0, 0, 0, 0.03), dark: (1, 1, 1, 0.03))
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
