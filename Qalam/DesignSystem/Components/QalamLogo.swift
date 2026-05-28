import SwiftUI
import AppKit

/// The قلم calligraphy as a template image, tinted by the caller. Loaded
/// once from the bundle and cached. Falls back to the SF Symbol speech bubble
/// if the resource is missing.
struct QalamLogo: View {
    var size: CGFloat = 18
    var tint: Color = QColors.accent

    var body: some View {
        if let nsImage = QalamLogo.cached {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(tint)
        } else {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: size * 0.75, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }

    // MARK: - Bundle loading

    private static let cached: NSImage? = {
        // Prefer NSImage(named:) so macOS pairs @2x automatically (when an
        // asset catalog is in play). When loading by URL, manually attach the
        // @2x rep so Retina mounts don't get pixelated downscales.
        if let img = NSImage(named: "OnboardingLogo") {
            img.isTemplate = true
            return img
        }
        guard let url1x = Bundle.main.url(forResource: "OnboardingLogo", withExtension: "png"),
              let img = NSImage(contentsOf: url1x)
        else { return nil }
        if let url2x = Bundle.main.url(forResource: "OnboardingLogo@2x", withExtension: "png"),
           let rep2x = NSImage(contentsOf: url2x)?.representations.first {
            rep2x.size = img.size  // size in points, not pixels
            img.addRepresentation(rep2x)
        }
        img.isTemplate = true
        return img
    }()
}
