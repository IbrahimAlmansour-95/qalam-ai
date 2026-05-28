import Foundation
import AppKit

/// One contextual issue found by NSSpellChecker — either a misspelling or a
/// grammar problem. Ranges are in the original input string.
struct GrammarIssue: Sendable, Equatable {
    enum Kind: Sendable { case spelling, grammar }
    let kind: Kind
    let originalText: String          // the wrong substring
    let replacement: String           // the proposed fix
    let nsRange: NSRange              // location/length in the input string
}

actor GrammarChecker {
    static let shared = GrammarChecker()

    private let language = "en"
    private var docTag: Int = NSSpellChecker.uniqueSpellDocumentTag()

    /// Runs an asynchronous spelling+grammar pass over `text`. Returns the
    /// FIRST issue whose end is at or just before `cursorOffset` — i.e. the
    /// thing the user just finished typing. Returns nil if there's no
    /// actionable issue at the cursor.
    func checkAtCursor(text: String, cursorOffset: Int) async -> GrammarIssue? {
        guard !text.isEmpty else { return nil }
        // Bound the scan to the last sentence-ish window for speed.
        let (window, windowStart) = recentWindow(of: text, around: cursorOffset)
        guard !window.isEmpty else { return nil }

        let issues = await runChecker(on: window)
        let localCursor = cursorOffset - windowStart
        // Prefer issues that end at or before the cursor and are within a few
        // chars of it (avoids surfacing fixes for text the user is still typing).
        let nearCursor = issues.first { issue in
            let end = issue.nsRange.location + issue.nsRange.length
            return end <= localCursor && (localCursor - end) <= 1
        } ?? issues.first
        guard let chosen = nearCursor else { return nil }

        // Translate the window-relative range back to the input range.
        let global = NSRange(
            location: chosen.nsRange.location + windowStart,
            length: chosen.nsRange.length
        )
        return GrammarIssue(
            kind: chosen.kind,
            originalText: chosen.originalText,
            replacement: chosen.replacement,
            nsRange: global
        )
    }

    /// Last sentence (or last 240 chars) ending at the cursor.
    private func recentWindow(of text: String, around cursor: Int) -> (String, Int) {
        let cur = max(0, min(text.count, cursor))
        let head = String(text.prefix(cur))
        // Walk backwards to find sentence start.
        var startIndex = head.startIndex
        if let lastTerm = head.lastIndex(where: { ".?!\n".contains($0) }) {
            startIndex = head.index(after: lastTerm)
        }
        var window = String(head[startIndex...]).trimmingCharacters(in: .whitespaces)
        if window.count > 240 {
            window = String(window.suffix(240))
        }
        // Compute the absolute offset where the window starts in `text`.
        let prefixLen = head.distance(from: head.startIndex, to: startIndex)
        return (window, prefixLen)
    }

    /// Synchronously invokes NSSpellChecker (it has a sync API for short text)
    /// and converts results into our GrammarIssue model.
    private func runChecker(on text: String) -> [GrammarIssue] {
        let checker = NSSpellChecker.shared
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let types = NSTextCheckingResult.CheckingType.spelling.rawValue
                  | NSTextCheckingResult.CheckingType.grammar.rawValue

        var orthography: NSOrthography?
        var wordCount: Int = 0
        let results = checker.check(
            text,
            range: fullRange,
            types: types,
            options: nil,
            inSpellDocumentWithTag: docTag,
            orthography: &orthography,
            wordCount: &wordCount
        )

        var out: [GrammarIssue] = []
        for result in results {
            guard result.range.location != NSNotFound,
                  result.range.length > 0,
                  result.range.location + result.range.length <= nsText.length
            else { continue }

            let original = nsText.substring(with: result.range)

            switch result.resultType {
            case .spelling:
                // Skip very short tokens — NSSpellChecker confidently rewrites
                // "df" → "of", "sf" → "if", etc., which is almost always wrong
                // for someone mid-typing. Require ≥ 4 letters before offering
                // a spelling fix.
                guard original.count >= 4 else { continue }
                let guesses = checker.guesses(
                    forWordRange: result.range,
                    in: text,
                    language: language,
                    inSpellDocumentWithTag: docTag
                ) ?? []
                guard let top = guesses.first,
                      top.lowercased() != original.lowercased() else { continue }
                // Require the suggestion to be reasonably close — guards against
                // wild substitutions where the original and suggestion share no
                // prefix at all.
                if !plausibleEdit(from: original, to: top) { continue }
                out.append(GrammarIssue(
                    kind: .spelling,
                    originalText: original,
                    replacement: top,
                    nsRange: result.range
                ))
            case .grammar:
                // grammarDetails: [[String: Any]] with "NSGrammarCorrections".
                let details = result.grammarDetails ?? []
                let suggestions: [String] = details.compactMap { dict in
                    (dict[NSGrammarCorrections] as? [String])?.first
                }
                guard let top = suggestions.first,
                      top != original else { continue }
                out.append(GrammarIssue(
                    kind: .grammar,
                    originalText: original,
                    replacement: top,
                    nsRange: result.range
                ))
            default:
                continue
            }
        }
        return out
    }

    /// Returns true when the just-typed character is a sentence terminator.
    nonisolated func isSentenceBoundary(_ char: Character) -> Bool {
        ".?!".contains(char)
    }

    /// Returns true when the proposed correction is a "small" edit relative to
    /// the original — same first letter, or edit distance ≤ 2. Filters out
    /// NSSpellChecker's more aggressive substitutions like "df" → "of".
    private func plausibleEdit(from original: String, to candidate: String) -> Bool {
        let a = original.lowercased()
        let b = candidate.lowercased()
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a.first == b.first { return true }
        return Self.editDistance(a, b) <= 2
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let s = Array(a)
        let t = Array(b)
        let m = s.count, n = t.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if s[i-1] == t[j-1] {
                    curr[j] = prev[j-1]
                } else {
                    curr[j] = 1 + min(prev[j-1], prev[j], curr[j-1])
                }
            }
            (prev, curr) = (curr, prev)
        }
        return prev[n]
    }
}
