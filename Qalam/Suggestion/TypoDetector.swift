import Foundation
import AppKit

/// Lightweight typo detection wrapper around NSSpellChecker.
enum TypoDetector {
    static func isLikelyMisspelled(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
        guard trimmed.count >= 3 else { return false }
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: trimmed, startingAt: 0)
        return range.location != NSNotFound
    }
}
