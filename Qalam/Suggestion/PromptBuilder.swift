import Foundation

enum PromptBuilder {
    static func build(textBeforeCursor: String,
                      styleContext: String,
                      mode: WritingMode,
                      maxWords: Int) -> String {
        let n = max(1, maxWords)
        // Range hint adapts to the user-configured ceiling so the prompt
        // matches what we actually want.
        let rangeHint: String
        if n == 1 { rangeHint = "ONLY the single next word" }
        else if n <= 3 { rangeHint = "ONLY the next 1-\(n) words" }
        else { rangeHint = "ONLY the next 1-\(n) words (prefer the shortest natural completion)" }

        let basePrompt = """
        You are an inline autocomplete engine, like macOS's built-in predictive text.

        TASK: Output \(rangeHint) the user is most likely to type next.

        HARD RULES:
        - Output AT MOST \(n) words. Never write a full sentence past that.
        - No preamble, no quotes, no explanation, no punctuation unless the very next \
          character is naturally punctuation.
        - Match the user's language EXACTLY. If they're writing in Arabic, respond in \
          Arabic. Spanish → Spanish. Hinglish (Hindi + English code-switching) → match. \
          Norwegian → Norwegian. Same script, same direction, same diacritics.
        - Match the user's existing tone, casing, and personal vocabulary.
        - If you are unsure or the user just finished a thought, output an empty line.
        - Do NOT rephrase what the user already typed.

        Examples (\(n) word budget):
          Input:  "I'll meet you at the"
          Output: "\(n >= 2 ? "office tomorrow" : "office")"

          Input:  "Hello my name is"
          Output: "Ibrahim"

          Input:  "اسمي إبراهيم وأنا"
          Output: "\(n >= 2 ? "أعمل في" : "أعمل")"
        """

        var parts: [String] = [basePrompt]
        if !mode.instruction.isEmpty && mode.id != WritingMode.neutral.id {
            parts.append("Mode: \(mode.name). \(mode.instruction)")
        }
        let trimmedStyle = styleContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStyle.isEmpty {
            parts.append("Recent style examples: \(trimmedStyle)")
        }
        parts.append(textBeforeCursor)
        return parts.joined(separator: "\n\n")
    }
}
