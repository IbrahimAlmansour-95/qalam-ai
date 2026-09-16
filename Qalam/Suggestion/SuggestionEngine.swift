import Foundation
import Observation

enum SuggestionKind: Sendable, Equatable {
    case llm
    case snippet(trigger: String)
    /// `:abc` partial matched an emoji shortcode. `typed` is what the user has
    /// at the cursor (e.g. `:smi`); `shortcode` is the canonical full key
    /// (`smile`) — we show both so the ghost text reads as the full match.
    case emoji(typed: String, shortcode: String, glyph: String)
    /// A contextual correction. `deleteCount` is how many backspace presses
    /// (`TextInjector.backspaceCount`) take the cursor back to the start of
    /// `original`; `trailing` is the text between the end of `original` and
    /// the cursor that should be re-typed after the replacement.
    case correction(original: String, replacement: String, deleteCount: Int, trailing: String, kind: GrammarIssue.Kind)
}

struct SuggestionResult: Sendable, Equatable {
    let text: String
    let words: [String]
    let basedOnContext: String
    let kind: SuggestionKind

    var firstWord: String? { words.first }
    var isEmpty: Bool { words.isEmpty }

    /// - Parameters:
    ///   - stopAtClause: "Short" completion length — keep only up to the end
    ///     of the first clause, so the ghost reads as a finished thought.
    ///   - suffix: what already follows the caret on the same line. The
    ///     completion has to fit BEFORE it, so any part of it the model
    ///     re-typed is removed.
    static func from(text: String,
                     context: String,
                     kind: SuggestionKind = .llm,
                     maxWords: Int = 5,
                     stopAtClause: Bool = false,
                     suffix: String? = nil) -> SuggestionResult {
        func empty() -> SuggestionResult {
            SuggestionResult(text: "", words: [], basedOnContext: context, kind: kind)
        }

        var cleaned = text
        if kind == .llm {
            // 1. Keep only the FIRST line — small models often ramble onto new
            //    lines or add a second sentence we don't want inline.
            if let nl = cleaned.firstIndex(where: { $0.isNewline }) {
                cleaned = String(cleaned[..<nl])
            }
            // 2. Drop a leading label the model sometimes emits
            //    ("Continuation:", "Output:", "Sure,", etc.).
            cleaned = stripLeadingLabel(cleaned)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip surrounding quotes the model occasionally adds.
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”«»"))

        if kind == .llm {
            // 3. Remove any echo of what the user already typed: if the model
            //    repeated the tail of the context, drop the overlapping prefix
            //    so the ghost is a genuine continuation, not a repeat.
            cleaned = stripContextEcho(cleaned, context: context)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            // 4. Mid-line: the completion has to fit BEFORE what already
            //    follows the caret, so drop anything the model re-typed of it.
            if let suffix {
                cleaned = stripFollowingEcho(cleaned, following: suffix)
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // 5. "Short": end at the first clause boundary.
            if stopAtClause {
                cleaned = clipAtClauseEnd(cleaned)
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !cleaned.isEmpty else { return empty() }

        // Belt + braces clip — models sometimes ignore the word budget.
        var tokens = cleaned.split(whereSeparator: { $0 == " " }).map(String.init)
        if kind == .llm, tokens.count > maxWords {
            tokens = Array(tokens.prefix(maxWords))
        }
        let final = tokens.joined(separator: " ")
        guard !final.isEmpty else { return empty() }
        return SuggestionResult(text: final, words: tokens, basedOnContext: context, kind: kind)
    }

    /// Strip a leading "label:"-style preamble or filler the model prepends.
    private static func stripLeadingLabel(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespaces)
        let labels = ["continuation:", "output:", "completion:", "answer:",
                      "sure,", "sure.", "here:", "here's", "here is"]
        let lower = out.lowercased()
        for label in labels where lower.hasPrefix(label) {
            out = String(out.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return out
    }

    /// If the completion repeats the trailing words of the context (a common
    /// small-model failure), drop that overlapping prefix so we only keep the
    /// genuinely new continuation.
    private static func stripContextEcho(_ completion: String, context: String) -> String {
        let ctx = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ctx.isEmpty, !completion.isEmpty else { return completion }
        let ctxLower = ctx.lowercased()
        let compLower = completion.lowercased()
        // Try the longest context suffix (up to 60 chars) that the completion
        // starts with, and strip it.
        let maxOverlap = min(60, min(ctxLower.count, compLower.count))
        if maxOverlap > 0 {
            for len in stride(from: maxOverlap, through: 3, by: -1) {
                let ctxSuffix = String(ctxLower.suffix(len))
                if compLower.hasPrefix(ctxSuffix) {
                    let idx = completion.index(completion.startIndex, offsetBy: len)
                    return String(completion[idx...])
                }
            }
        }
        return completion
    }

    /// Where a "short" completion is allowed to end (the punctuation itself is
    /// kept, so the ghost reads naturally).
    private static let clauseTerminators: Set<Character> = [
        ".", ",", ";", ":", "!", "?", "،", "؛", "؟",
    ]

    /// Keep only up to (and including) the first clause boundary.
    private static func clipAtClauseEnd(_ text: String) -> String {
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            let next = text.index(after: index)
            if clauseTerminators.contains(ch), index > text.startIndex {
                // Not a decimal point or thousands separator inside a number.
                let previous = text[text.index(before: index)]
                let following = next < text.endIndex ? text[next] : " "
                if (ch == "." || ch == ","), previous.isNumber, following.isNumber {
                    index = next
                    continue
                }
                return String(text[...index])
            }
            index = next
        }
        return text
    }

    /// Mid-line completions must not duplicate the text that already follows
    /// the caret: drop a completion that simply retypes it, and otherwise trim
    /// the tail of the completion that runs into it.
    private static func stripFollowingEcho(_ completion: String, following suffix: String) -> String {
        let after = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !after.isEmpty, !completion.isEmpty else { return completion }
        let afterLower = after.lowercased()
        let compLower = completion.lowercased()
        // The whole completion is just the start of what's already there.
        if afterLower.hasPrefix(compLower) { return "" }
        let maxOverlap = min(compLower.count, afterLower.count)
        guard maxOverlap >= 3 else { return completion }
        for len in stride(from: maxOverlap, through: 3, by: -1) {
            if afterLower.hasPrefix(String(compLower.suffix(len))) {
                return String(completion.dropLast(len))
            }
        }
        return completion
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

    /// The backend a side request (the alternatives list) should use, so it
    /// never ends up on a different engine than the inline suggestion.
    var activeBackend: any LLMBackend { backend }

    /// The field context the current suggestion was built from — what the
    /// alternatives list asks about, and what tells it the user has moved on.
    var lastContextForAlternatives: TextContext { lastContext }

    private let debouncer: Debouncer
    private var consumeTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var lastContext: TextContext = .empty
    /// How many times the user has cycled alternatives for the current context.
    private var cycleCount = 0
    /// Bumped on every model request. A stream only publishes — and on error
    /// only dismisses — while it is still the latest request, so a timed-out
    /// or superseded stream can never leave (or wipe) a ghost it doesn't own.
    private var requestGeneration = 0
    /// Esc with "Dismiss and pause this field": no suggestions for this field
    /// until the time passes, focus moves to another field, or the user
    /// forces one.
    private var escPause: (key: FieldKey, until: Date)?
    /// The context force-activate just read. The stream delivers the same
    /// context too (before or after the forced run); the forced run owns it.
    private var forcedContext: TextContext?
    /// Field of the last force-activate. While the automatic rules keep that
    /// field idle, the forced suggestion is still trimmed as the user types
    /// through it and accepted word by word — no new one starts on its own.
    private var forcedField: FieldKey?

    static let escPauseSeconds: TimeInterval = 15

    private init() {
        self.debouncer = Debouncer()
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

    private func handle(context: TextContext, forced: Bool = false) async {
        if !forced, let pending = forcedContext {
            if pending == context { return }
            forcedContext = nil
        }
        if forcedField != nil, forcedField != context.fieldKey {
            forcedField = nil
        }
        let prefs = UserPreferences.shared
        // Effective per-app / per-site settings (site > app > global).
        let profile = ProfileStore.shared.noteActive(context)

        // Secure Input, password fields, global pause / snooze, app or site
        // Off / paused, Force only and the idle rules: one decision.
        switch ActivationPolicy.evaluate(context, profile: profile, forced: forced) {
        case .allow:
            break
        case .idle where context.fieldKey == forcedField && currentSuggestion != nil:
            followForcedSuggestion(context)
            return
        case .idle, .blocked:
            dismiss()
            return
        }

        // Don't suggest while the user has an active text selection (they're
        // about to replace/act on it, not continue typing).
        if context.selectionLength > 0 {
            dismiss()
            return
        }
        // Esc paused this field (opt-in Esc behaviour).
        if let pause = escPause {
            if pause.until <= Date() || pause.key != context.fieldKey {
                escPause = nil
            } else if !forced {
                dismiss()
                return
            }
        }
        // Trigger threshold: need at least N chars in the line being typed.
        let lineStart = context.textBeforeCursor.lastIndex(where: { $0.isNewline })
        let line = lineStart.map { String(context.textBeforeCursor[context.textBeforeCursor.index(after: $0)...]) } ?? context.textBeforeCursor
        if !forced, line.count < prefs.triggerThreshold {
            dismiss()
            return
        }
        // Smarter triggers: skip when the current word looks like a URL, an
        // email mid-entry, a file path, or a code-ish token — autocomplete
        // there is noise, not help. (Forcing asks for one anyway.)
        if !forced, Self.looksLikeNonProse(SuggestionEngine.lastToken(of: line)) {
            dismiss()
            return
        }

        // Keep the visible ghost in sync with typing IMMEDIATELY (before the
        // debounced model call), so a stale suggestion never lingers or follows
        // the caret. If the user typed the next character(s) of the current
        // suggestion, trim them so the ghost shrinks seamlessly; if they typed
        // something else (or finished), clear it at once.
        if let current = currentSuggestion, case .llm = current.kind {
            currentSuggestion = Self.advance(current,
                                             from: lastContext.textBeforeCursor,
                                             to: context.textBeforeCursor)
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

        // Language preference: stay quiet while the user types the other
        // language. Checked after the snippet / emoji pre-empt, which the
        // user triggers explicitly with ":".
        if Self.isOtherLanguage(line, preference: profile.languagePreference) {
            await debouncer.cancel()
            dismiss()
            return
        }

        let activeTag = prefs.activeModelTag
        let autoCorrect = profile.autocorrectEnabled
        // "Complete mid-line" turned off: no new completion while text still
        // follows the caret on this line. Spelling / grammar fixes (which are
        // about what's BEFORE the caret) and snippets are unaffected, and a
        // forced request always goes through.
        let allowCompletion = forced || prefs.midLineCompletion
            || !context.sameLineSuffix.contains(where: { !$0.isWhitespace })
        // Delay read at schedule time, so the Settings slider applies live.
        // A forced request doesn't wait.
        await debouncer.schedule(delayMs: forced ? 0 : prefs.suggestionDelayMs) { [weak self] in
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
            // Superseded while the (possibly slow) proof-read ran: a newer
            // keystroke already scheduled its own request — don't cancel that
            // one's stream for this stale context.
            guard !Task.isCancelled else { return }
            guard allowCompletion else {
                await self?.dismiss()
                return
            }
            await self?.requestSuggestion(context: context, model: activeTag, profile: profile)
        }
    }

    /// An idle field (Force only, search box…) showing a forced suggestion:
    /// keep it in step with typing and accepts, but never start a new one.
    private func followForcedSuggestion(_ context: TextContext) {
        guard let current = currentSuggestion else { return }
        if case .llm = current.kind {
            currentSuggestion = Self.advance(current,
                                             from: lastContext.textBeforeCursor,
                                             to: context.textBeforeCursor)
        } else if context.textBeforeCursor != lastContext.textBeforeCursor {
            // Snippet / emoji / correction offsets belong to the old text.
            currentSuggestion = nil
        }
        lastContext = context
        cycleCount = 0
        if currentSuggestion == nil {
            dismiss()
        }
    }

    /// True when a language preference is set and the word being typed is
    /// clearly in the other script. Words without letters never count.
    static func isOtherLanguage(_ line: String, preference: LanguagePreference) -> Bool {
        guard preference != .auto else { return false }
        switch Script.dominant(in: lastToken(of: line)) {
        case .arabic:  return preference == .english
        case .latin:   return preference == .arabic
        case .unknown: return false
        }
    }

    private func checkForCorrection(context: TextContext) async -> SuggestionResult? {
        let text = context.textBeforeCursor
        // UTF-16, like NSSpellChecker's ranges.
        let cursor = (text as NSString).length

        // Fast path: NSSpellChecker (typos + obvious grammar). Effective for
        // English/Latin; macOS's Arabic dictionary is too lenient to catch much.
        if let local = await GrammarChecker.shared.checkAtCursor(text: text, cursorOffset: cursor) {
            return buildCorrection(from: local, in: text, cursor: cursor)
        }

        // LLM sentence-level proof-pass (fires only at a finished sentence).
        // Runs automatically for ARABIC — the local LLM is the only thing that
        // can correct Arabic, since NSSpellChecker effectively can't — and for
        // any language when the user opts into grammar checking.
        let arabic = Self.isArabicDominant(text)
        if (arabic || UserPreferences.shared.autoGrammarEnabled),
           let issue = await llmGrammarCheck(text: text) {
            return buildCorrection(from: issue, in: text, cursor: cursor)
        }
        return nil
    }

    /// `cursor` is the UTF-16 length of `text` (the caret sits at its end).
    private func buildCorrection(from issue: GrammarIssue,
                                 in text: String,
                                 cursor: Int) -> SuggestionResult? {
        // Compute how to apply the fix by replaying it as backspace + retype.
        let issueEnd = issue.nsRange.location + issue.nsRange.length
        guard issueEnd <= cursor else { return nil }
        // Backspaces are counted the way the host app deletes (a Character
        // per press, Arabic harakat one by one) — not in UTF-16 units.
        let startIdx = AccessibilityMonitor.characterIndex(forUTF16Offset: issue.nsRange.location, in: text)
        let deleteCount = TextInjector.backspaceCount(for: text[startIdx...])
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
    /// Sentence terminators, including Arabic question mark (؟) and full stop (۔).
    private static let sentenceTerminators: Set<Character> = [".", "?", "!", "؟", "۔"]

    /// True when the recent text is predominantly Arabic script.
    static func isArabicDominant(_ text: String) -> Bool {
        Script.dominant(in: text.suffix(80)) == .arabic
    }

    private func llmGrammarCheck(text: String) async -> GrammarIssue? {
        // Require the user to have just landed on a post-sentence space
        // (terminator + space) — works for English (.?!) and Arabic (؟ ۔).
        let trimmed = text
        guard let lastTwo = trimmed.suffix(2).first,
              trimmed.hasSuffix(" "),
              Self.sentenceTerminators.contains(lastTwo) else { return nil }

        // Take the most recent finished sentence (everything from the second-to-
        // last terminator + 1 through the last terminator inclusive).
        let withoutTrailingSpace = String(trimmed.dropLast())
        let head = String(withoutTrailingSpace) // ends in terminator
        var sentenceStart = head.startIndex
        let body = head.dropLast()               // up to (but not including) terminator
        if let prevTerm = body.lastIndex(where: { Self.sentenceTerminators.contains($0) || $0 == "\n" }) {
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
                stop: ["\n\n", "Sentence:", "Response:"],
                deadline: LLMDeadline.proofread
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
        // The sentence just finished is the LAST occurrence.
        let range = nsText.range(of: sentence, options: .backwards)
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
        // Re-resolved rather than cached, so an edit made since (mode,
        // instructions) applies to the alternative too.
        let profile = ProfileStore.shared.resolve(bundleID: lastContext.appBundleID,
                                                  host: lastContext.host)
        Task { [lastContext] in
            await requestSuggestion(context: lastContext,
                                    model: UserPreferences.shared.activeModelTag,
                                    profile: profile,
                                    temperatureOverride: temp,
                                    avoidText: avoid)
        }
    }

    private func requestSuggestion(context: TextContext,
                                   model: String,
                                   profile: ResolvedProfile,
                                   temperatureOverride: Double? = nil,
                                   avoidText: String? = nil) async {
        streamTask?.cancel()
        requestGeneration &+= 1
        let generation = requestGeneration
        let mode = WritingModeStore.shared.mode(id: profile.writingModeID)
        let entry = ModelRegistry.entry(forTag: model)
        let modelMax = entry?.maxSuggestionWords ?? 5
        let maxWords = min(max(1, UserPreferences.shared.maxSuggestionWords), modelMax)
        // Token budget = words × ~1.6 (English) + small headroom for partial
        // words. Arabic needs more: its words tokenize into roughly half again
        // as many pieces, so the same budget arrives cut off mid-word. The
        // word clip below still bounds what is shown.
        let arabicContext = Script.dominant(in: context.textBeforeCursor.suffix(80)) == .arabic
        let perWord = arabicContext ? 2.4 : 1.6
        let maxTokens = max(4, Int(Double(maxWords) * perWord) + 2)
        // "Short" also ends at the first clause boundary.
        let stopAtClause = CompletionLength.from(words: maxWords, modelMax: modelMax).stopsAtClause

        let style = await StyleContextBuffer.shared.recentContext()
        let prefs = UserPreferences.shared
        // Mid-line: what the completion has to fit in front of. nil when the
        // caret is at the end of its line, or the user turned mid-line
        // completion off (then `handle` never gets this far unforced).
        let sameLineSuffix = context.sameLineSuffix
        let midLineSuffix = (prefs.midLineCompletion
                             && sameLineSuffix.contains(where: { !$0.isWhitespace }))
            ? sameLineSuffix : nil

        // Gather opt-in context sources.
        // The AX-based sources are skipped while the frontmost app has tripped
        // the slow-AX breaker.
        let frontPID = AXGuard.frontmostPID()
        let axAvailable = !AXGuard.isBackedOff(frontPID)
        let clipboard = prefs.clipboardContextEnabled
            ? ClipboardContextProvider.recentText() : nil
        let surrounding = (prefs.broaderContextEnabled && axAvailable)
            ? AccessibilityMonitor.shared.surroundingText() : nil
        var screen: String? = nil
        if prefs.screenContextEnabled && axAvailable {
            let caret = AXGuard.measure(pid: frontPID) { AccessibilityMonitor.shared.caretFrame() }
            screen = await ScreenOCRContext.shared.visualContext(around: caret)
        }
        // Personalization (off by default): a few short excerpts of the
        // user's own writing, budgeted by strength. In-memory work inside the
        // store actor — no file or keychain IO on this path.
        let strength = prefs.personalizationStrength
        var personalization: String? = nil
        if strength != .off {
            personalization = await PersonalizationStore.shared.promptContext(
                currentText: context.textBeforeCursor,
                bundleID: context.appBundleID,
                host: context.host,
                strength: strength)
        }
        // Superseded (newer request or dismiss) while gathering context.
        guard requestGeneration == generation else { return }
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
            personalInfo: PersonalInfoStore.shared.promptBlock(),
            userInstructions: profile.customInstructions,
            languagePreference: profile.languagePreference,
            personalization: personalization,
            includeStyleContext: strength != .off,
            sameLineSuffix: midLineSuffix
        )
        // When cycling, steer the model away from the option just shown.
        if let avoid = avoidText, !avoid.isEmpty {
            prompt += "\n\nProvide a DIFFERENT continuation than: \"\(avoid)\""
        }
        // Inline completion wants on-context, near-deterministic output, so cap
        // the temperature low (a creative mode's higher temp drifts off-topic
        // for autocomplete). Cycling for an alternative passes an explicit
        // higher override.
        let temperature = temperatureOverride ?? min(mode.temperature, 0.2)

        isStreaming = true
        var assembled = ""

        streamTask = Task { [weak self, backend, maxWords, stopAtClause, midLineSuffix] in
            do {
                for try await token in backend.complete(
                    prompt: prompt,
                    model: model,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    stop: ["\n", "\n\n", "###"],
                    deadline: LLMDeadline.completion
                ) {
                    try Task.checkCancellation()
                    assembled += token
                    let trimmed = assembled.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, self?.requestGeneration == generation {
                        self?.publish(SuggestionResult.from(text: trimmed,
                                                            context: context.textBeforeCursor,
                                                            maxWords: maxWords,
                                                            stopAtClause: stopAtClause,
                                                            suffix: midLineSuffix))
                    }
                }
                if let s = self, s.requestGeneration == generation,
                   let shown = s.currentSuggestion, !shown.isEmpty {
                    await UsageLogger.shared.recordShownSuggestion()
                }
            } catch is CancellationError {
                // ignore
            } catch {
                // Backend error or deadline (LLMTimeoutError) — clear the
                // suggestion silently, but only if this is still the latest
                // request (a newer one owns the ghost otherwise).
                if self?.requestGeneration == generation {
                    self?.dismiss()
                }
            }
            self?.markStreamFinished()
        }
    }

    /// Reconcile the current ghost with new typing. Returns the (possibly
    /// trimmed) suggestion to keep showing, or nil to clear it.
    ///   • typed the next chars of the suggestion → trim them (ghost shrinks)
    ///   • typed something else, deleted, or finished → nil (clear)
    static func advance(_ s: SuggestionResult, from old: String, to new: String) -> SuggestionResult? {
        guard new.hasPrefix(old) else { return nil }            // deletion / jump → clear
        let typed = String(new.dropFirst(old.count))
        if typed.isEmpty { return s }                            // caret/selection change only → keep
        guard s.text.hasPrefix(typed) else { return nil }        // diverged → clear
        let remaining = String(s.text.dropFirst(typed.count))
        guard !remaining.isEmpty else { return nil }             // fully typed out → clear
        return SuggestionResult(
            text: remaining,
            words: remaining.split(separator: " ").map(String.init),
            basedOnContext: new,
            kind: s.kind
        )
    }

    private func publish(_ result: SuggestionResult) {
        // Nothing new appears while Secure Input is on.
        guard !SecureInputMonitor.shared.isActive else { return }
        // …or in a field the user just paused with Esc (a request that was
        // already on its way must not bring the ghost back).
        if let pause = escPause, pause.until > Date(), pause.key == lastContext.fieldKey { return }
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
            TextInjector.shared.replaceBeforeCursor(
                deleteCount: TextInjector.backspaceCount(for: trigger) + 1, // ':' + trigger
                with: suggestion.text)
            Task { await UsageLogger.shared.recordAcceptedWord(suggestion.text) }
            currentSuggestion = nil
            return suggestion.text
        }

        // Emoji acceptance: delete the typed ":partial" and replace with the glyph.
        if case .emoji(let typed, _, let glyph) = suggestion.kind {
            TextInjector.shared.replaceBeforeCursor(
                deleteCount: TextInjector.backspaceCount(for: typed) + 1, // ':' + typed
                with: glyph)
            Task { await UsageLogger.shared.recordAcceptedWord(glyph) }
            currentSuggestion = nil
            return glyph
        }

        // Correction acceptance: backspace to the start of the wrong text,
        // type the replacement, then re-type whatever the user had typed after
        // it. NSSpellChecker is highly accurate at word level, so this is safe.
        if case .correction(_, let replacement, let deleteCount, let trailing, _) = suggestion.kind {
            TextInjector.shared.replaceBeforeCursor(deleteCount: deleteCount, with: replacement + trailing)
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
        // "Only text where I accepted a suggestion" (T6 default mode).
        WritingRecorder.shared.noteAccepted()

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
        WritingRecorder.shared.noteAccepted()
        currentSuggestion = nil
        return text
    }

    /// ⌃ + the key above Tab: suggest in the focused field right now,
    /// skipping the idle rules, the trigger length, an Esc pause and Force
    /// only. Returns the decision so the shortcut can say why nothing
    /// happens; nil while Secure Input is on (the keyboard is not ours then).
    @discardableResult
    func forceActivate() -> ActivationDecision? {
        guard !SecureInputMonitor.shared.isActive else { return nil }
        escPause = nil
        let context = AccessibilityMonitor.shared.snapshot()
        let profile = ProfileStore.shared.resolve(
            bundleID: context.appBundleID,
            host: KnownApps.isBrowser(context.appBundleID) ? context.host : nil)
        let decision = ActivationPolicy.evaluate(context, profile: profile, forced: true)
        guard decision == .allow else {
            QLog.debug(.suggestion, "force-activate refused")
            return decision
        }
        forcedContext = context
        forcedField = context.fieldKey
        QLog.debug(.suggestion, "force-activate")
        Task { await handle(context: context, forced: true) }
        return decision
    }

    /// Esc with the "Dismiss and pause this field" behaviour.
    func dismissAndPauseField() {
        let field = lastContext
        dismiss()
        guard field != .empty else { return }
        escPause = (field.fieldKey, Date().addingTimeInterval(Self.escPauseSeconds))
        // A request scheduled just before Esc shouldn't even run.
        Task { await debouncer.cancel() }
    }

    func dismiss() {
        streamTask?.cancel()
        // Also invalidates a request still gathering context (OCR/style), so
        // it can't bring the ghost back after Esc / Secure Input.
        requestGeneration &+= 1
        currentSuggestion = nil
    }
}
