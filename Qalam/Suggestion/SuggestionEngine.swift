import Foundation
import Observation

enum SuggestionKind: Sendable, Equatable {
    case llm
    case snippet(trigger: String)
    /// `:abc` partial matched an emoji shortcode. `typed` is what the user has
    /// at the cursor (e.g. `:smi`); `shortcode` is the canonical full key
    /// (`smile`) — we show both so the ghost text reads as the full match.
    case emoji(typed: String, shortcode: String, glyph: String)
    /// A contextual correction. `deleteCount` is how many characters to
    /// backspace from the current cursor to reach the start of `original`;
    /// `trailing` is the text between the end of `original` and the cursor
    /// that should be re-typed after the replacement.
    case correction(original: String, replacement: String, deleteCount: Int, trailing: String, kind: GrammarIssue.Kind)
}

struct SuggestionResult: Sendable, Equatable {
    let text: String
    let words: [String]
    let basedOnContext: String
    let kind: SuggestionKind

    var firstWord: String? { words.first }
    var isEmpty: Bool { words.isEmpty }

    static func from(text: String,
                     context: String,
                     kind: SuggestionKind = .llm,
                     maxWords: Int = 5) -> SuggestionResult {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip surrounding quotes the model occasionally adds.
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        guard !cleaned.isEmpty else {
            return SuggestionResult(text: "", words: [], basedOnContext: context, kind: kind)
        }
        // Belt + braces clip — models sometimes ignore the prompt and run on.
        var tokens = cleaned.split(whereSeparator: { $0 == " " }).map(String.init)
        if kind == .llm, tokens.count > maxWords {
            tokens = Array(tokens.prefix(maxWords))
        }
        let final = tokens.joined(separator: " ")
        return SuggestionResult(text: final, words: tokens, basedOnContext: context, kind: kind)
    }
}

@MainActor
@Observable
final class SuggestionEngine {
    static let shared = SuggestionEngine()

    private(set) var currentSuggestion: SuggestionResult?
    private(set) var isStreaming = false

    private let ollamaBackend: any LLMBackend = OllamaBackend()
    private let appleBackend: any LLMBackend = AppleIntelligenceBackend()

    /// Resolves the active backend from preferences, falling back to Ollama
    /// when Apple Intelligence is selected but unavailable.
    private var backend: any LLMBackend {
        if UserPreferences.shared.engine == "appleIntelligence",
           AppleIntelligenceBackend.isAvailable {
            return appleBackend
        }
        return ollamaBackend
    }

    private let debouncer: Debouncer
    private var consumeTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var lastContext: TextContext = .empty
    /// How many times the user has cycled alternatives for the current context.
    private var cycleCount = 0

    private init() {
        self.debouncer = Debouncer(intervalMs: Constants.Suggestion.defaultDelayMs)
    }

    func start() {
        consumeTask?.cancel()
        consumeTask = Task { [weak self] in
            guard let stream = await self?.subscribeToContext() else { return }
            for await context in stream {
                await self?.handle(context: context)
            }
        }
    }

    private func subscribeToContext() async -> AsyncStream<TextContext> {
        AccessibilityMonitor.shared.contextStream()
    }

    private func handle(context: TextContext) async {
        let prefs = UserPreferences.shared

        // Excluded apps
        if let bundle = context.appBundleID, prefs.excludedBundleIDs.contains(bundle) {
            dismiss()
            return
        }
        if !prefs.isEnabled || prefs.isSnoozed {
            dismiss()
            return
        }
        // Trigger threshold: need at least N chars in the line being typed.
        let lineStart = context.textBeforeCursor.lastIndex(where: { $0.isNewline })
        let line = lineStart.map { String(context.textBeforeCursor[context.textBeforeCursor.index(after: $0)...]) } ?? context.textBeforeCursor
        if line.count < prefs.triggerThreshold {
            dismiss()
            return
        }
        // Don't suggest while the user has an active text selection (they're
        // about to replace/act on it, not continue typing).
        if context.cursorIndex == 0, context.textBeforeCursor.isEmpty,
           !context.fullText.isEmpty {
            // caret at very start with content after — likely a selection; skip.
        }
        // Smarter triggers: skip when the current word looks like a URL, an
        // email mid-entry, a file path, or a code-ish token — autocomplete
        // there is noise, not help.
        if Self.looksLikeNonProse(SuggestionEngine.lastToken(of: line)) {
            dismiss()
            return
        }

        lastContext = context
        cycleCount = 0   // fresh context — reset the alternative cycle

        // Snippet pre-empt: if the line ends with ":<trigger>" (no trailing space yet),
        // surface the expansion immediately — no LLM call needed.
        if let snippetResult = matchSnippet(in: context.textBeforeCursor) {
            currentSuggestion = snippetResult
            await debouncer.cancel()
            streamTask?.cancel()
            return
        }

        // Emoji pre-empt: same shape, but matches against the bundled emoji
        // shortcode map. Wins over the LLM whenever the user is mid-shortcode.
        if let emojiResult = matchEmoji(in: context.textBeforeCursor) {
            currentSuggestion = emojiResult
            await debouncer.cancel()
            streamTask?.cancel()
            return
        }

        let activeTag = prefs.activeModelTag
        let autoCorrect = prefs.autoCorrectEnabled
        await debouncer.schedule { [weak self] in
            // Run a spelling/grammar pass first — these are local, fast, and
            // only present when NSSpellChecker is confident, so they don't
            // "randomly autocorrect". If nothing is found we fall through to
            // the regular LLM completion.
            if autoCorrect {
                if let correction = await self?.checkForCorrection(context: context) {
                    await self?.publish(correction)
                    return
                }
            }
            await self?.requestSuggestion(context: context, model: activeTag)
        }
    }

    private func checkForCorrection(context: TextContext) async -> SuggestionResult? {
        let text = context.textBeforeCursor
        let cursor = text.count

        // Fast path: NSSpellChecker (typos + obvious grammar).
        if let local = await GrammarChecker.shared.checkAtCursor(text: text, cursorOffset: cursor) {
            return buildCorrection(from: local, in: text, cursor: cursor)
        }

        // Slower path: LLM sentence-level grammar fix. Only triggers right after
        // the user has finished a sentence (so we have something complete to
        // proof-read) and only when the user has explicitly opted in.
        if UserPreferences.shared.autoGrammarEnabled,
           let issue = await llmGrammarCheck(text: text) {
            return buildCorrection(from: issue, in: text, cursor: cursor)
        }
        return nil
    }

    private func buildCorrection(from issue: GrammarIssue,
                                 in text: String,
                                 cursor: Int) -> SuggestionResult? {
        // Compute how to apply the fix by replaying it as backspace + retype.
        let issueEnd = issue.nsRange.location + issue.nsRange.length
        guard issueEnd <= cursor else { return nil }
        let deleteCount = cursor - issue.nsRange.location
        let nsText = text as NSString
        let trailing = nsText.substring(with: NSRange(
            location: issueEnd,
            length: nsText.length - issueEnd
        ))
        let replacement = issue.replacement
        return SuggestionResult(
            text: replacement,
            words: [replacement],
            basedOnContext: text,
            kind: .correction(
                original: issue.originalText,
                replacement: replacement,
                deleteCount: deleteCount,
                trailing: trailing,
                kind: issue.kind
            )
        )
    }

    /// Fires only when the user just typed a sentence terminator followed by
    /// a space. Asks the model to rewrite the just-finished sentence and only
    /// surfaces a fix if the rewrite is materially different.
    private func llmGrammarCheck(text: String) async -> GrammarIssue? {
        // Require the user to have just landed on a post-sentence space.
        let trimmed = text
        guard let lastTwo = trimmed.suffix(2).first,
              trimmed.hasSuffix(" "),
              ".?!".contains(lastTwo) else { return nil }

        // Take the most recent finished sentence (everything from the second-to-
        // last terminator + 1 through the last terminator inclusive).
        let withoutTrailingSpace = String(trimmed.dropLast())
        let head = String(withoutTrailingSpace) // ends in terminator
        var sentenceStart = head.startIndex
        let body = head.dropLast()               // up to (but not including) terminator
        if let prevTerm = body.lastIndex(where: { ".?!\n".contains($0) }) {
            sentenceStart = head.index(after: prevTerm)
        }
        let sentence = String(head[sentenceStart...]).trimmingCharacters(in: .whitespaces)
        guard sentence.count >= 12, sentence.count <= 280 else { return nil }

        // Tight, high-precision prompt:
        //   * model is told to fix ONLY clear errors
        //   * preserve meaning, tone, length, casing, punctuation style
        //   * return "OK" if nothing wrong — must be exact
        //   * no commentary
        let prompt = """
        You are a strict proofreader. Read the user's sentence and decide whether \
        it contains a CLEAR spelling, grammar, or punctuation error.

        Rules:
        1. If the sentence is correct or only stylistically debatable, respond with \
        exactly: OK
        2. Otherwise, output the corrected sentence on a single line. Preserve the \
        user's tone, casing, punctuation style, and length.
        3. Do not add explanations, quotes, or formatting.
        4. Never introduce content the user didn't write.

        Sentence: \(sentence)
        Response:
        """

        let model = UserPreferences.shared.activeModelTag
        var assembled = ""
        do {
            for try await token in backend.complete(
                prompt: prompt,
                model: model,
                maxTokens: 80,
                temperature: 0.0,            // deterministic
                stop: ["\n\n", "Sentence:", "Response:"]
            ) {
                try Task.checkCancellation()
                assembled += token
                if assembled.count > 400 { break }
            }
        } catch {
            return nil
        }

        // Tight acceptance criteria so the LLM can't be too eager.
        let trimmedReply = assembled
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        guard !trimmedReply.isEmpty,
              trimmedReply.uppercased() != "OK",
              !trimmedReply.uppercased().hasPrefix("OK "),
              !trimmedReply.uppercased().hasPrefix("OK."),
              normalize(trimmedReply) != normalize(sentence),
              // Don't accept rewrites that change length wildly — that's usually
              // the model paraphrasing instead of correcting.
              Double(abs(trimmedReply.count - sentence.count)) /
                  Double(max(sentence.count, 1)) < 0.4
        else { return nil }

        // Locate the sentence range in the original text.
        let nsText = text as NSString
        let nsSentence = sentence as NSString
        let range = nsText.range(of: sentence)
        guard range.location != NSNotFound, range.length == nsSentence.length else { return nil }

        return GrammarIssue(
            kind: .grammar,
            originalText: sentence,
            replacement: trimmedReply,
            nsRange: range
        )
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    /// Last whitespace-delimited token of a line.
    static func lastToken(of line: String) -> String {
        String(line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last ?? "")
    }

    /// Heuristic: is this token a URL / email / path / code identifier where
    /// inline prose completion would be unhelpful?
    static func looksLikeNonProse(_ token: String) -> Bool {
        guard token.count >= 3 else { return false }
        let lower = token.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") { return true }
        if token.contains("@") && token.contains(".") { return true }            // email in progress
        if token.hasPrefix("/") || token.hasPrefix("~/") || token.hasPrefix("./") { return true } // path
        if token.contains("://") { return true }
        // code-ish: camelCase / snake_case / has () [] {} ; = etc.
        if token.contains("()") || token.contains("_") && token.contains(".") { return true }
        let codeSymbols = CharacterSet(charactersIn: "{}();=<>")
        if token.unicodeScalars.contains(where: { codeSymbols.contains($0) }) { return true }
        return false
    }

    private func matchEmoji(in textBeforeCursor: String) -> SuggestionResult? {
        // Find a token at the end of the form ":xyz" with at least one letter.
        var tail = ""
        for ch in textBeforeCursor.reversed() {
            if ch == ":" {
                tail = String(ch) + tail
                break
            }
            if ch.isWhitespace { return nil }
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                tail = String(ch) + tail
            } else {
                return nil
            }
        }
        guard tail.hasPrefix(":"), tail.count >= 2 else { return nil }
        let partial = String(tail.dropFirst())
        // Avoid colliding with snippets: snippet store wins if there's a match.
        if SnippetStore.shared.match(trigger: partial) != nil { return nil }
        guard let (shortcode, glyph) = EmojiResolver.default.bestPrefixMatch(for: partial) else {
            return nil
        }
        // Ghost text shows the rest of the shortcode + the emoji glyph, e.g.
        // typing ":smi" shows "le 🙂".
        let visible = ":\(shortcode) \(glyph)"
        return SuggestionResult(
            text: visible,
            words: [visible],
            basedOnContext: textBeforeCursor,
            kind: .emoji(typed: partial, shortcode: shortcode, glyph: glyph)
        )
    }

    private func matchSnippet(in textBeforeCursor: String) -> SuggestionResult? {
        // Find the last ":xxx" token at the cursor with no space after.
        var tail = ""
        for ch in textBeforeCursor.reversed() {
            if ch == ":" {
                tail = String(ch) + tail
                break
            }
            if ch.isWhitespace { return nil }
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                tail = String(ch) + tail
            } else {
                return nil
            }
        }
        guard tail.hasPrefix(":"), tail.count >= 2 else { return nil }
        let trigger = String(tail.dropFirst())
        guard let snippet = SnippetStore.shared.match(trigger: trigger) else { return nil }
        let expanded = SnippetVariables.expand(snippet.expansion)
        return SuggestionResult(
            text: expanded,
            words: expanded.split(separator: " ").map(String.init),
            basedOnContext: textBeforeCursor,
            kind: .snippet(trigger: trigger)
        )
    }

    /// Cycle to an alternative completion for the SAME context — used by the
    /// "next suggestion" key. Re-runs the model with a higher temperature and
    /// an instruction to avoid the current text, so the user gets a genuinely
    /// different option. Only meaningful for LLM completions.
    func cycleAlternative() {
        guard let current = currentSuggestion, !current.isEmpty else { return }
        guard case .llm = current.kind else { return }
        guard !lastContext.textBeforeCursor.isEmpty else { return }
        cycleCount += 1
        let avoid = current.text
        let temp = min(0.95, 0.4 + Double(cycleCount) * 0.2)
        Task { [lastContext] in
            await requestSuggestion(context: lastContext,
                                    model: UserPreferences.shared.activeModelTag,
                                    temperatureOverride: temp,
                                    avoidText: avoid)
        }
    }

    private func requestSuggestion(context: TextContext,
                                   model: String,
                                   temperatureOverride: Double? = nil,
                                   avoidText: String? = nil) async {
        streamTask?.cancel()
        let mode = WritingModeStore.shared.mode(id: UserPreferences.shared.activeModeID)
        let entry = ModelRegistry.entry(forTag: model)
        let modelMax = entry?.maxSuggestionWords ?? 5
        let maxWords = min(max(1, UserPreferences.shared.maxSuggestionWords), modelMax)
        // Token budget = words × ~1.6 (English) + small headroom for partial words.
        let maxTokens = max(4, Int(Double(maxWords) * 1.6) + 2)

        let style = await StyleContextBuffer.shared.recentContext()
        let prefs = UserPreferences.shared

        // Gather opt-in context sources.
        let clipboard = prefs.clipboardContextEnabled
            ? ClipboardContextProvider.recentText() : nil
        let surrounding = prefs.broaderContextEnabled
            ? AccessibilityMonitor.shared.surroundingText() : nil
        var screen: String? = nil
        if prefs.screenContextEnabled {
            let caret = AccessibilityMonitor.shared.caretFrame()
            screen = await ScreenOCRContext.shared.visualContext(around: caret)
        }
        // Don't feed the clipboard back if it's just what the user already typed.
        let clipboardContext = (clipboard.map { !context.textBeforeCursor.contains($0) } ?? false)
            ? clipboard : nil

        var prompt = PromptBuilder.build(
            textBeforeCursor: context.textBeforeCursor,
            styleContext: style,
            mode: mode,
            maxWords: maxWords,
            appName: context.appName,
            textAfterCursor: context.textAfterCursor,
            surroundingContext: surrounding,
            clipboardContext: clipboardContext,
            screenContext: screen,
            personalInfo: PersonalInfoStore.shared.promptBlock()
        )
        // When cycling, steer the model away from the option just shown.
        if let avoid = avoidText, !avoid.isEmpty {
            prompt += "\n\nProvide a DIFFERENT continuation than: \"\(avoid)\""
        }
        let temperature = temperatureOverride ?? mode.temperature

        isStreaming = true
        var assembled = ""

        streamTask = Task { [weak self, backend, maxWords] in
            do {
                for try await token in backend.complete(
                    prompt: prompt,
                    model: model,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    stop: ["\n\n", "###"]
                ) {
                    try Task.checkCancellation()
                    assembled += token
                    let trimmed = assembled.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        await self?.publish(SuggestionResult.from(text: trimmed,
                                                                  context: context.textBeforeCursor,
                                                                  maxWords: maxWords))
                    }
                }
                if let s = self, await s.currentSuggestion != nil, !s.currentSuggestion!.isEmpty {
                    await UsageLogger.shared.recordShownSuggestion()
                }
            } catch is CancellationError {
                // ignore
            } catch {
                // backend error — clear suggestion silently
                await self?.dismiss()
            }
            await self?.markStreamFinished()
        }
    }

    private func publish(_ result: SuggestionResult) {
        // Only show if user hasn't typed past the context this was based on.
        guard lastContext.textBeforeCursor.hasSuffix(result.basedOnContext) ||
              lastContext.textBeforeCursor == result.basedOnContext
        else { return }
        currentSuggestion = result
    }

    private func markStreamFinished() {
        isStreaming = false
    }

    // MARK: - User actions

    /// Accept the next word in the current suggestion. Returns the word inserted,
    /// or nil if there was no suggestion.
    @discardableResult
    func acceptNextWord() -> String? {
        guard let suggestion = currentSuggestion, !suggestion.isEmpty else { return nil }

        // Snippet acceptance is "atomic": delete the typed ":trigger" and inject
        // the full expansion, even on a single Tab.
        if case .snippet(let trigger) = suggestion.kind {
            TextInjector.shared.deleteBackwards(count: trigger.count + 1) // ':' + trigger
            TextInjector.shared.injectWord(suggestion.text, withTrailingSpace: false)
            Task { await UsageLogger.shared.recordAcceptedWord(suggestion.text) }
            currentSuggestion = nil
            return suggestion.text
        }

        // Emoji acceptance: delete the typed ":partial" and replace with the glyph.
        if case .emoji(let typed, _, let glyph) = suggestion.kind {
            TextInjector.shared.deleteBackwards(count: typed.count + 1) // ':' + typed
            TextInjector.shared.injectWord(glyph, withTrailingSpace: false)
            Task { await UsageLogger.shared.recordAcceptedWord(glyph) }
            currentSuggestion = nil
            return glyph
        }

        // Correction acceptance: backspace to the start of the wrong text,
        // type the replacement, then re-type whatever the user had typed after
        // it. NSSpellChecker is highly accurate at word level, so this is safe.
        if case .correction(_, let replacement, let deleteCount, let trailing, _) = suggestion.kind {
            TextInjector.shared.deleteBackwards(count: deleteCount)
            TextInjector.shared.injectWord(replacement + trailing, withTrailingSpace: false)
            Task { await UsageLogger.shared.recordAcceptedWord(replacement) }
            currentSuggestion = nil
            return replacement
        }

        let word = suggestion.words[0]
        let remaining = Array(suggestion.words.dropFirst())
        // Add the trailing space only on the LAST word of a multi-word
        // suggestion (between words we always need the separator), and only
        // when the user opted in.
        let isLast = remaining.isEmpty
        let trailingSpace = isLast ? UserPreferences.shared.spaceAfterAccept : true
        TextInjector.shared.injectWord(word, withTrailingSpace: trailingSpace)
        Task { await UsageLogger.shared.recordAcceptedWord(word) }
        Task { await StyleContextBuffer.shared.append(word) }

        if remaining.isEmpty {
            currentSuggestion = nil
        } else {
            currentSuggestion = SuggestionResult(
                text: remaining.joined(separator: " "),
                words: remaining,
                basedOnContext: suggestion.basedOnContext + word + " ",
                kind: .llm
            )
        }
        return word
    }

    @discardableResult
    func acceptAll() -> String? {
        guard let suggestion = currentSuggestion, !suggestion.isEmpty else { return nil }
        if case .snippet = suggestion.kind {
            return acceptNextWord()
        }
        if case .emoji = suggestion.kind {
            return acceptNextWord()
        }
        if case .correction = suggestion.kind {
            return acceptNextWord()
        }
        let text = suggestion.text
        TextInjector.shared.injectWord(text, withTrailingSpace: false)
        Task {
            for w in suggestion.words {
                await UsageLogger.shared.recordAcceptedWord(w)
                await StyleContextBuffer.shared.append(w)
            }
        }
        currentSuggestion = nil
        return text
    }

    func dismiss() {
        streamTask?.cancel()
        currentSuggestion = nil
    }
}
