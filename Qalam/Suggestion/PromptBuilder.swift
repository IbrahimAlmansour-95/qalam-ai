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
                      personalInfo: String? = nil,
                      userInstructions: String? = nil,
                      languagePreference: LanguagePreference = .auto,
                      personalization: String? = nil,
                      includeStyleContext: Bool = false,
                      sameLineSuffix: String? = nil) -> String {
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
        // Steer the language to the script the user is CURRENTLY typing, not the
        // dominant language of the surrounding text. Without this, after writing
        // a paragraph of Arabic and switching to English, the model keeps
        // completing in Arabic (and vice-versa). A small model only obeys this
        // when the directive is forceful AND the final "Continuation" label is
        // tagged with the language (which primes the first token) — see below.
        // Steer by the CURRENT word (trailing token), so a short English word
        // after Arabic still flips the language.
        let lastToken = textBeforeCursor
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).last
        let detected = lastToken.map { Script.dominant(in: $0) } ?? .unknown
        // A per-app / per-site language preference pins the language even
        // when the last token has no letters (digits, punctuation).
        let script: Script
        switch languagePreference {
        case .auto:    script = detected
        case .arabic:  script = .arabic
        case .english: script = .latin
        }
        let pinned = script != detected
        switch script {
        case .arabic:
            prompt += pinned ? "\nReply in Arabic only — no English."
                             : "\nThe last word is Arabic, so reply in Arabic only — no English."
        case .latin:
            prompt += pinned ? "\nReply in English only — no Arabic."
                             : "\nThe last word is English, so reply in English only — no Arabic."
        case .unknown: break
        }

        // Cheap, high-signal hints only.
        var hints: [String] = []
        if let appName, !appName.isEmpty {
            hints.append("App: \(appName).")
        }
        if mode.id != WritingMode.neutral.id, !mode.instruction.isEmpty {
            hints.append("Tone: \(mode.instruction)")
        }
        if let instructions = compactInstructions(userInstructions) {
            hints.append("Follow the user's instructions: \(instructions)")
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
        // Personalization (opt-in, T6). The accepted-word buffer is a cheap
        // signal we already keep; the excerpts come from the encrypted
        // writing store and are budgeted by strength before they get here.
        if includeStyleContext {
            let style = styleContext.trimmingCharacters(in: .whitespacesAndNewlines)
            if !style.isEmpty {
                background.append("Words the user often accepts: \(String(style.suffix(120)))")
            }
        }
        if let personal = personalization?.trimmingCharacters(in: .whitespacesAndNewlines),
           !personal.isEmpty {
            background.append(personal)
        }
        if !background.isEmpty {
            prompt += "\n\nBackground (context only, do not copy):\n" + background.joined(separator: "\n")
        }

        // The cursor sits in the MIDDLE of a line: the completion has to fill
        // the gap, so say so plainly and forbid repeating what follows — a
        // small model otherwise re-types the rest of the line.
        if let midLine = sameLineSuffix?.trimmingCharacters(in: .whitespacesAndNewlines),
           !midLine.isEmpty {
            prompt += "\n\nThe cursor is mid-line. Write only what belongs between the text and "
                + "what follows it on the same line: \(String(midLine.prefix(80))). "
                + "Never repeat that following text."
        } else if let after = textAfterCursor?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !after.isEmpty {
            prompt += "\n\nYour continuation must fit before this following text: \(String(after.prefix(80)))"
        }

        // Language-tagged label primes the model to begin in the right script.
        let contLabel: String
        switch script {
        case .arabic:  contLabel = "Continuation (Arabic):"
        case .latin:   contLabel = "Continuation (English):"
        case .unknown: contLabel = "Continuation:"
        }
        prompt += "\n\nText:\n\(tail)\n\n\(contLabel)"
        return prompt
    }

    /// Longest instruction text sent to the model (≈100–150 tokens). Global
    /// instructions alone always fit (the UI caps them at the same length).
    static let maxInstructionChars = 500

    /// Custom instructions as one line: lines joined with "; ", ending in
    /// punctuation so the next hint doesn't run into it. Over budget, the
    /// START is dropped — global text comes first and the app / site
    /// instructions after it are the more specific ones. nil when empty.
    private static func compactInstructions(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var text = raw
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
        guard !text.isEmpty else { return nil }
        if text.count > maxInstructionChars {
            text = String(text.suffix(maxInstructionChars))
            // Start at a word boundary.
            if let space = text.firstIndex(of: " ") {
                text = String(text[text.index(after: space)...])
            }
        }
        if let last = text.last, !".!?؟;:".contains(last) {
            text += "."
        }
        return text
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
