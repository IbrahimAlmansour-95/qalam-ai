import Foundation

enum PromptBuilder {
    static func build(textBeforeCursor: String,
                      styleContext: String,
                      mode: WritingMode,
                      maxWords: Int,
                      appName: String? = nil,
                      textAfterCursor: String? = nil,
                      surroundingContext: String? = nil,
                      clipboardContext: String? = nil,
                      screenContext: String? = nil) -> String {
        let n = max(1, maxWords)

        // Target length nudge — get the model to actually USE the budget for
        // multi-word completions when the context allows, instead of always
        // taking the easy 1-word route.
        let lengthDirective: String
        if n == 1 {
            lengthDirective = "Output ONLY the single next word."
        } else if n <= 3 {
            lengthDirective = "Output the next 2-\(n) words when possible — at minimum the next word."
        } else {
            lengthDirective = "Output the next 3-\(n) words to give the user a useful, contextual continuation. Never output a full sentence past \(n) words."
        }

        let basePrompt = """
        You are an inline autocomplete engine, like macOS's built-in QuickType predictive text.

        TASK: Given the user's text so far, output the next words they are most \
        likely to type, written in the SAME tone, casing, language, and style.

        \(lengthDirective)

        HARD RULES:
        - Never write more than \(n) words.
        - Never repeat or paraphrase what the user already typed. Begin with the \
          NEXT word after their cursor, not a rewording of what's there.
        - No preamble, no quotes, no labels, no explanation.
        - No trailing punctuation unless the next character is naturally punctuation.
        - Match the user's language EXACTLY (English → English, Arabic → Arabic, \
          Spanish → Spanish, Hinglish → Hinglish, Norwegian → Norwegian).
        - If you are genuinely unsure, output an empty line.

        Good examples (\(n)-word budget):
          Input:  "Hi my name is"
          Output: "\(n >= 3 ? "Ibrahim and I" : (n >= 2 ? "Ibrahim Almansour" : "Ibrahim"))"

          Input:  "Please find attached the"
          Output: "\(n >= 3 ? "document you requested" : (n >= 2 ? "document you" : "document"))"

          Input:  "I'll meet you at the"
          Output: "\(n >= 3 ? "office at three" : (n >= 2 ? "office tomorrow" : "office"))"

          Input:  "اسمي إبراهيم وأنا"
          Output: "\(n >= 3 ? "أعمل في الرياض" : (n >= 2 ? "أعمل في" : "أعمل"))"
        """

        var parts: [String] = [basePrompt]
        // Telling the model which app the user is in materially improves
        // relevance — completions in Mail read like email, in a chat app like
        // a message, in Xcode like code. Costs nothing (no extra permission).
        if let appName, !appName.isEmpty {
            parts.append("The user is typing in the app: \(appName). Match how people write there.")
        }
        if !mode.instruction.isEmpty && mode.id != WritingMode.neutral.id {
            parts.append("Mode: \(mode.name). \(mode.instruction)")
        }
        let trimmedStyle = styleContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStyle.isEmpty {
            parts.append("Recent style examples (match this voice): \(trimmedStyle)")
        }
        // Optional context sources — each is bounded by its provider and only
        // present when the user enabled it. They inform the completion but the
        // model must still continue ONLY from the cursor.
        if let surrounding = surroundingContext?.trimmingCharacters(in: .whitespacesAndNewlines),
           !surrounding.isEmpty {
            parts.append("Nearby on-screen text (for context, do not repeat):\n\(surrounding)")
        }
        if let screen = screenContext?.trimmingCharacters(in: .whitespacesAndNewlines),
           !screen.isEmpty {
            parts.append("Visible text around the cursor (for context, do not repeat):\n\(screen)")
        }
        if let clip = clipboardContext?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty {
            parts.append("The user's clipboard (may be relevant, do not repeat verbatim):\n\(clip)")
        }
        if let after = textAfterCursor?.trimmingCharacters(in: .whitespacesAndNewlines),
           !after.isEmpty {
            parts.append("Text that comes AFTER the cursor (your continuation must fit before it):\n\(after)")
        }
        parts.append("User's text so far:\n\(textBeforeCursor)")
        parts.append("Your output (next \(n == 1 ? "word only" : "1-\(n) words only"), nothing else):")
        return parts.joined(separator: "\n\n")
    }
}
