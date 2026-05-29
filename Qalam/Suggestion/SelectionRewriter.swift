import Foundation
import AppKit
import ApplicationServices

/// Tones the user can rewrite a selection into.
enum RewriteTone: String, CaseIterable, Identifiable, Sendable {
    case formal, casual, concise, expand, grammar

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .formal:  return "briefcase"
        case .casual:  return "face.smiling"
        case .concise: return "scissors"
        case .expand:  return "text.append"
        case .grammar: return "checkmark.seal"
        }
    }

    var localizationKey: LocalizationKey {
        switch self {
        case .formal:  return .rewriteToneFormal
        case .casual:  return .rewriteToneCasual
        case .concise: return .rewriteToneConcise
        case .expand:  return .rewriteToneExpand
        case .grammar: return .rewriteToneGrammar
        }
    }

    var instruction: String {
        switch self {
        case .formal:
            return "Rewrite the text in a more formal, professional tone."
        case .casual:
            return "Rewrite the text in a friendly, casual, conversational tone."
        case .concise:
            return "Rewrite the text to be more concise and clear, removing redundancy."
        case .expand:
            return "Expand the text with a little more detail while keeping the same intent."
        case .grammar:
            return "Fix spelling, grammar, and punctuation mistakes in the text."
        }
    }
}

/// Reads the current selection from the focused app, rewrites it with the LLM
/// in a chosen tone, and writes the result back over the selection.
@MainActor
@Observable
final class SelectionRewriter {
    static let shared = SelectionRewriter()

    enum State: Equatable {
        case idle
        case working(RewriteTone)
        case failed(String)
    }
    private(set) var state: State = .idle

    private let ollamaBackend: any LLMBackend = OllamaBackend()
    private let appleBackend: any LLMBackend = AppleIntelligenceBackend()

    /// The element + selected text captured when the picker opened, so a later
    /// tone choice still targets the right place even if focus shifts to our
    /// panel.
    private var capturedElement: AXUIElement?
    private var capturedText: String = ""

    private init() {}

    private var backend: any LLMBackend {
        if UserPreferences.shared.engine == "appleIntelligence",
           AppleIntelligenceBackend.isAvailable {
            return appleBackend
        }
        return ollamaBackend
    }

    /// Entry point bound to the global hotkey. Captures the selection and shows
    /// the tone picker if there's something selected.
    func begin() {
        // Toggle: pressing the hotkey again closes the picker.
        if ToneRewritePanel.shared.isVisible {
            cancel()
            return
        }
        guard let (element, text) = readSelection(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 4000
        else {
            NSSound.beep()
            return
        }
        capturedElement = element
        capturedText = text
        state = .idle
        let anchor = AccessibilityMonitor.shared.caretFrame()
        ToneRewritePanel.shared.show(near: anchor)
    }

    /// Run the rewrite for the captured selection and replace it in place.
    func apply(tone: RewriteTone) {
        guard let element = capturedElement, !capturedText.isEmpty else { return }
        let original = capturedText
        state = .working(tone)
        Task {
            do {
                let rewritten = try await rewrite(original, tone: tone)
                let clean = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else {
                    state = .failed("Empty result")
                    return
                }
                replaceSelection(in: element, with: clean)
                state = .idle
                ToneRewritePanel.shared.hide()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        ToneRewritePanel.shared.hide()
        state = .idle
        capturedElement = nil
        capturedText = ""
    }

    // MARK: - LLM

    private func rewrite(_ text: String, tone: RewriteTone) async throws -> String {
        let prompt = """
        \(tone.instruction)
        Keep the same language as the input. Preserve meaning and any names.
        Return ONLY the rewritten text with no preamble, quotes, or explanation.

        Text:
        \(text)

        Rewritten:
        """
        let maxTokens = max(32, min(512, text.count / 2 + 64))
        var assembled = ""
        for try await token in backend.complete(
            prompt: prompt,
            model: UserPreferences.shared.activeModelTag,
            maxTokens: maxTokens,
            temperature: 0.4,
            stop: ["\n\n\n"]
        ) {
            assembled += token
        }
        return assembled
    }

    // MARK: - Accessibility read / write

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused
        else { return nil }
        return (el as! AXUIElement)
    }

    private func readSelection() -> (AXUIElement, String)? {
        guard let element = focusedElement() else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String
        else { return nil }
        return (element, text)
    }

    private func replaceSelection(in element: AXUIElement, with text: String) {
        let err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        if err != .success {
            // Fallback: type over the current selection.
            TextInjector.shared.injectWord(text, withTrailingSpace: false)
        }
    }
}
