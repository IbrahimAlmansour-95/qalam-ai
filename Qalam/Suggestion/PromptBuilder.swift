import Foundation

/// Builds a LEAN inline-completion prompt.
///
/// Design (mirrors how Cotypist and other good local autocompletes behave):
/// small local models complete best when the prompt is short and dominated by
/// the user's *immediate* text — not buried under instructions and injected
/// context. So we lead with a one-line instruction, add only cheap high-signal
/// hints (app, mode), and put the recent text last so the model just continues
/// it. Heavy/optional context (clipboard, screen OCR, nearby UI text) is
/// included only briefly as background, because for a 5B model it more often
/// pulls the completion off-topic than helps.
enum PromptBuilder {
    static func build(textBeforeCursor: String,
                      styleContext: String,
                      mode: WritingMode,
                      maxWords: Int,
                      appName: String? = nil,
                      textAfterCursor: String? = nil,
                      surroundingContext: String? = nil,
                      clipboardContext: String? = nil,
                      screenContext: String? = nil,
                      personalInfo: String? = nil) -> String {
        let n = max(1, maxWords)

        // The immediate text is what matters most. Feed the tail (a paragraph
        // or two), starting at a word boundary, not the whole document.
        let tail = recentTail(textBeforeCursor, maxChars: 480)

        let countPhrase = n == 1 ? "the single next word" : "the next \(n) words or fewer"
        var prompt = """
        Continue the text below. Output ONLY \(countPhrase) the user would most \
        likely type next — in the same language, casing, and tone. Do not repeat \
        what is already written, and do not add quotes, labels, or explanations.
        """

        // Cheap, high-signal hints only.
        var hints: [String] = []
        if let appName, !appName.isEmpty {
            hints.append("App: \(appName).")
        }
        if mode.id != WritingMode.neutral.id, !mode.instruction.isEmpty {
            hints.append("Tone: \(mode.instruction)")
        }
        if let info = personalInfo?.trimmingCharacters(in: .whitespacesAndNewlines),
           !info.isEmpty {
            hints.append("User details (use only if they're clearly typing them): \(info)")
        }
        if !hints.isEmpty {
            prompt += "\n" + hints.joined(separator: " ")
        }

        // Optional context — brief background only, hard-capped so it can't
        // dominate the immediate text. Each is opt-in via settings.
        var background: [String] = []
        if let s = surroundingContext?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            background.append(String(s.suffix(220)))
        }
        if let c = clipboardContext?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            background.append("Clipboard: \(String(c.suffix(160)))")
        }
        if let sc = screenContext?.trimmingCharacters(in: .whitespacesAndNewlines), !sc.isEmpty {
            background.append(String(sc.suffix(160)))
        }
        if !background.isEmpty {
            prompt += "\n\nBackground (context only, do not copy):\n" + background.joined(separator: "\n")
        }

        if let after = textAfterCursor?.trimmingCharacters(in: .whitespacesAndNewlines), !after.isEmpty {
            prompt += "\n\nYour continuation must fit before this following text: \(String(after.prefix(80)))"
        }

        prompt += "\n\nText:\n\(tail)\n\nContinuation:"
        return prompt
    }

    /// The trailing slice of the text, beginning at a word boundary, so the
    /// model sees recent local context rather than the entire document.
    private static func recentTail(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let slice = String(text.suffix(maxChars))
        // Start at the next space so we don't begin mid-word.
        if let spaceIdx = slice.firstIndex(of: " ") {
            return String(slice[slice.index(after: spaceIdx)...])
        }
        return slice
    }
}
