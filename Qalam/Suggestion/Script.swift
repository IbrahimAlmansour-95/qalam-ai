import Foundation

/// Writing-script detection shared across the app — caret placement, language
/// steering, correction routing, and dictionary selection all need to know
/// "is this Arabic or Latin?". Keeping ONE canonical set of Unicode ranges here
/// stops the per-call-site copies from drifting (they previously disagreed on a
/// couple of presentation-form ranges).
enum Script {
    case arabic, latin, unknown

    static func isArabic(_ u: UInt32) -> Bool {
        (0x0600...0x06FF).contains(u)   // Arabic
            || (0x0750...0x077F).contains(u)   // Arabic Supplement
            || (0x08A0...0x08FF).contains(u)   // Arabic Extended-A
            || (0xFB50...0xFDFF).contains(u)   // Presentation Forms-A
            || (0xFE70...0xFEFF).contains(u)   // Presentation Forms-B
    }

    static func isLatin(_ u: UInt32) -> Bool {
        (0x0041...0x005A).contains(u) || (0x0061...0x007A).contains(u)
    }

    /// Whichever script has more letters in `text` (ties / none → `.unknown`).
    static func dominant<S: StringProtocol>(in text: S) -> Script {
        var arabic = 0, latin = 0
        for s in text.unicodeScalars {
            if isArabic(s.value) { arabic += 1 }
            else if isLatin(s.value) { latin += 1 }
        }
        if arabic == 0 && latin == 0 { return .unknown }
        return arabic > latin ? .arabic : .latin
    }

    /// The first strong directional character → base (paragraph) direction.
    static func firstStrong<S: StringProtocol>(in text: S) -> Script {
        for s in text.unicodeScalars {
            if isArabic(s.value) { return .arabic }
            if isLatin(s.value) { return .latin }
        }
        return .unknown
    }

    /// True if `text` contains any Arabic letters.
    static func containsArabic<S: StringProtocol>(in text: S) -> Bool {
        text.unicodeScalars.contains { isArabic($0.value) }
    }
}
