import Foundation
import AppKit

/// "What else could come next?" — a short numbered list of alternative next
/// words or phrases, shown under the caret and inserted with 1…5.
///
/// It is a side request, not part of the inline suggestion stream: the ghost
/// keeps whatever it had, the list is drawn instead of it while it is open,
/// and closing the list brings the ghost back. Nothing is ever inserted
/// without a keypress.
@MainActor
final class AlternativesProvider {
    static let shared = AlternativesProvider()

    private(set) var options: [String] = []
    private(set) var isLoading = false

    private var task: Task<Void, Never>?
    /// Text before the caret when the list was opened. If the user types on,
    /// the list no longer describes what's on screen and is closed.
    private var contextText = ""
    private var anchor: AlternativesPanel.Anchor?

    static let maxOptions = 5
    /// How much of the user's text the model is shown.
    private static let contextTail = 300
    /// Longest option we will list (a rambling line is not an alternative).
    private static let maxOptionChars = 40
    private static let maxReplyChars = 400

    private init() {}

    // MARK: - Open / close

    /// Opens the list for the current field. `auto` marks the version the
    /// overlay loop triggers after a pause in typing.
    func show(auto: Bool = false) {
        guard !SecureInputMonitor.shared.isActive else { return }
        let context = SuggestionEngine.shared.lastContextForAlternatives
        let before = context.textBeforeCursor
        guard !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let anchor = currentAnchor() else { return }

        task?.cancel()
        self.anchor = anchor
        contextText = before
        // Seed with the word the ghost is already offering, so option 1 is
        // never empty and the list is useful before the model answers.
        options = Self.seedOptions(from: SuggestionEngine.shared.currentSuggestion)
        isLoading = true
        AlternativesPanel.shared.show(options: options, loading: true, anchor: anchor)
        QLog.debug(.suggestion, "alternatives list opened (\(auto ? "auto" : "shortcut"))")

        let backend = SuggestionEngine.shared.activeBackend
        let model = UserPreferences.shared.activeModelTag
        let prompt = Self.prompt(for: before)
        task = Task { [weak self] in
            var assembled = ""
            do {
                for try await token in backend.complete(
                    prompt: prompt,
                    model: model,
                    maxTokens: 48,
                    temperature: 0.7,
                    stop: ["\n\n"],
                    deadline: LLMDeadline.alternatives
                ) {
                    try Task.checkCancellation()
                    assembled += token
                    if assembled.count > Self.maxReplyChars { break }
                }
            } catch is CancellationError {
                return
            } catch {
                // Timeout or backend error: keep whatever the seed gave us.
                assembled = ""
            }
            guard !Task.isCancelled else { return }
            self?.finish(reply: assembled, context: before)
        }
    }

    /// Closes the list and drops any request still running.
    func close() {
        task?.cancel()
        task = nil
        guard AlternativesPanel.shared.isVisible || !options.isEmpty else { return }
        options = []
        isLoading = false
        anchor = nil
        contextText = ""
        AlternativesPanel.shared.hide()
    }

    /// Called from the overlay loop while the list is up: the user moved on
    /// (clicked elsewhere, focus changed) → the list is stale.
    func revalidate() {
        guard AlternativesPanel.shared.isVisible else { return }
        if SuggestionEngine.shared.lastContextForAlternatives.textBeforeCursor != contextText {
            close()
        }
    }

    // MARK: - Insert

    /// Inserts option `index` (1-based) at the caret, exactly the way an
    /// accepted word is inserted.
    func insert(index: Int) {
        let slot = index - 1
        guard slot >= 0, slot < options.count else { return }
        let option = options[slot]
        close()
        TextInjector.shared.injectWord(option,
                                       withTrailingSpace: UserPreferences.shared.spaceAfterAccept)
        SuggestionEngine.shared.dismiss()
        WritingRecorder.shared.noteAccepted()
        Task {
            await UsageLogger.shared.recordAcceptedWord(option)
            await StyleContextBuffer.shared.append(option)
        }
    }

    // MARK: - Request

    private func finish(reply: String, context: String) {
        guard AlternativesPanel.shared.isVisible else { return }
        // The user kept typing while the model answered.
        guard SuggestionEngine.shared.lastContextForAlternatives.textBeforeCursor == context else {
            close()
            return
        }
        let parsed = Self.parse(reply,
                                lastWord: SuggestionEngine.lastToken(of: context),
                                seed: options)
        isLoading = false
        guard !parsed.isEmpty, let anchor else {
            close()
            return
        }
        options = parsed
        AlternativesPanel.shared.show(options: parsed, loading: false, anchor: anchor)
    }

    /// Prompt for the list. Same language steering as `PromptBuilder`, so the
    /// options come back in the script the user is typing.
    private static func prompt(for text: String) -> String {
        let tail = String(text.suffix(contextTail))
        let lastToken = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).last
        var prompt = """
        Suggest 5 different words or short phrases (1–3 words each) that could come next in \
        the text. Same language as the text. One per line. No numbering, quotes or explanations.
        """
        switch lastToken.map({ Script.dominant(in: $0) }) ?? .unknown {
        case .arabic:
            prompt += "\nThe last word is Arabic, so reply in Arabic only — no English."
        case .latin:
            prompt += "\nThe last word is English, so reply in English only — no Arabic."
        case .unknown:
            break
        }
        prompt += "\n\nText:\n\(tail)\n\nNext:"
        return prompt
    }

    /// The first word of the inline suggestion, when there is an LLM one.
    private static func seedOptions(from suggestion: SuggestionResult?) -> [String] {
        guard let suggestion, !suggestion.isEmpty, case .llm = suggestion.kind,
              let first = suggestion.firstWord
        else { return [] }
        let cleaned = cleanOption(first)
        return cleaned.isEmpty ? [] : [cleaned]
    }

    /// One option per line: strip numbering / bullets / quotes, keep 1–3 word
    /// entries, drop echoes of the word being typed, dedupe case-insensitively.
    static func parse(_ reply: String, lastWord: String, seed: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        let lastLower = lastWord.lowercased()

        func add(_ raw: some StringProtocol) {
            guard out.count < maxOptions else { return }
            let cleaned = cleanOption(String(raw))
            guard !cleaned.isEmpty, cleaned.count <= maxOptionChars else { return }
            let words = cleaned.split(separator: " ")
            guard (1...3).contains(words.count) else { return }
            let key = cleaned.lowercased()
            guard key != lastLower, !seen.contains(key) else { return }
            seen.insert(key)
            out.append(cleaned)
        }

        for option in seed { add(option) }
        for line in reply.split(whereSeparator: { $0.isNewline }) { add(line) }
        return out
    }

    /// "1. word", "- word", "\"word\"" → "word".
    private static func cleanOption(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        // Leading "1." / "2)" / "3-".
        var index = text.startIndex
        while index < text.endIndex, text[index].isNumber {
            index = text.index(after: index)
        }
        if index > text.startIndex, index < text.endIndex, ".)-".contains(text[index]) {
            text = String(text[text.index(after: index)...])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        // Bullets.
        while let first = text.first, "-•*–—".contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”«»"))
        // Collapse any internal whitespace so the word count is honest.
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Anchor

    /// Where to hang the list: the caret if it can be read, else the mirror
    /// bubble, else the focused field. nil = nothing to point at.
    private func currentAnchor() -> AlternativesPanel.Anchor? {
        if MirrorBubblePanel.shared.isVisible {
            let frame = MirrorBubblePanel.shared.frame
            return AlternativesPanel.Anchor(rect: frame, isRTL: isRTLField())
        }
        let pid = AXGuard.frontmostPID()
        guard !AXGuard.isBackedOff(pid) else { return nil }
        let monitor = AccessibilityMonitor.shared
        if let caret = AXGuard.measure(pid: pid, { monitor.caretFrame() }) {
            return AlternativesPanel.Anchor(rect: caret, isRTL: isRTLField())
        }
        if let field = AXGuard.measure(pid: pid, { monitor.focusedFrame() }) {
            return AlternativesPanel.Anchor(rect: field, isRTL: isRTLField())
        }
        return nil
    }

    /// The field's own writing direction, from the text already in it.
    private func isRTLField() -> Bool {
        let context = SuggestionEngine.shared.lastContextForAlternatives
        return Script.firstStrong(in: context.textBeforeCursor.suffix(200)) == .arabic
    }
}
