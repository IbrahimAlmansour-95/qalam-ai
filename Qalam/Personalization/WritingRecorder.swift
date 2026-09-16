import Foundation
import AppKit

/// Captures what the user writes, so completions can sound like them.
///
/// Off by default. A "session" is one stretch of typing in one field; when it
/// ends (focus moves, the app changes, the field is cleared on send, or 20 s
/// of silence) the text the user actually inserted is stored — encrypted — by
/// `PersonalizationStore`.
///
/// Never recorded: password fields, anything while Secure Input is on, apps
/// or sites set to Off / paused, profiles with "Learn from my writing" off
/// (terminals by default), text shorter than 40 characters, documents larger
/// than 20 000 units (the diff would be meaningless), and — in the default
/// mode — anything the user didn't accept a suggestion in.
@MainActor
final class WritingRecorder {
    static let shared = WritingRecorder()

    /// A session ends after this much silence.
    static let idleTimeout: TimeInterval = 20
    /// Text shorter than this is not worth a sample.
    static let minCharacters = 40
    /// Minimum letters, so "..........." or a row of digits never counts.
    static let minLetters = 5
    /// Longest stored sample.
    static let maxSampleCharacters = 2_000
    /// Documents above this size are skipped (a bounded value read makes the
    /// prefix/suffix diff meaningless).
    static let maxDocumentUnits = 20_000

    private struct Session {
        let key: FieldKey
        let bundleID: String
        let host: String?
        let startText: String
        var lastText: String
        var lastActivity: Date
        var accepted: Bool
        /// The longest inserted run seen so far — chat fields clear on send,
        /// so the last reading is often empty.
        var bestSegment: String
        var context: TextContext
        var oversized: Bool
    }

    private var session: Session?
    /// A field we already decided not to record, so the settings aren't
    /// resolved again on every keystroke there.
    private var rejectedKey: FieldKey?
    private var consumeTask: Task<Void, Never>?
    private var idleTimer: Timer?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        consumeTask = Task { [weak self] in
            guard let stream = self?.subscribe() else { return }
            for await context in stream {
                self?.handle(context)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                WritingRecorder.shared.endSession(commit: true)
            }
        }
    }

    /// The idle check only runs while a session is open — a feature that is
    /// off by default shouldn't wake the CPU every few seconds.
    private func startIdleTimer() {
        guard idleTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { _ in
            Task { @MainActor in WritingRecorder.shared.checkIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func subscribe() -> AsyncStream<TextContext> {
        AccessibilityMonitor.shared.contextStream()
    }

    /// The user accepted a model suggestion in the field being recorded.
    func noteAccepted() {
        session?.accepted = true
        session?.lastActivity = Date()
    }

    /// A personalization setting changed: re-evaluate the current field on
    /// the next keystroke instead of trusting the earlier decision.
    func settingsChanged() {
        rejectedKey = nil
        if !UserPreferences.shared.recordWritingEnabled { endSession(commit: false) }
    }

    // MARK: - Session tracking

    private func handle(_ context: TextContext) {
        guard UserPreferences.shared.recordWritingEnabled else {
            if session != nil { endSession(commit: false) }
            return
        }
        // Nothing readable (no text element, Secure Input, AX backoff): close
        // whatever was open rather than diffing against a stale reading.
        guard context != .empty, let bundleID = context.appBundleID else {
            endSession(commit: true)
            return
        }
        guard bundleID != Constants.bundleID else { return }

        if var current = session, current.key == context.fieldKey {
            let previousUnits = current.lastText.utf16.count
            let nowUnits = context.fullText.utf16.count
            current.lastText = context.fullText
            current.lastActivity = Date()
            current.context = context
            if !current.oversized {
                let segment = Self.insertedSegment(from: current.startText, to: context.fullText)
                if segment.count > current.bestSegment.count { current.bestSegment = segment }
            }
            session = current
            // Sent / cleared / selected-and-deleted: the field loses at least
            // half its length in one step. Commit what we have and start a
            // fresh session from what's left.
            if previousUnits > 0, nowUnits * 2 < previousUnits {
                endSession(commit: true)
                beginSession(context, bundleID: bundleID)
            }
            return
        }

        // A different field (or the first one).
        endSession(commit: true)
        beginSession(context, bundleID: bundleID)
    }

    private func beginSession(_ context: TextContext, bundleID: String) {
        guard rejectedKey != context.fieldKey else { return }
        // Resolve once at the start too, so a password field or an app set to
        // Off never has its text held in memory at all.
        let profile = ProfileStore.shared.resolve(
            bundleID: bundleID,
            host: KnownApps.isBrowser(bundleID) ? context.host : nil)
        guard ActivationPolicy.allowsRecording(context, profile: profile) else {
            rejectedKey = context.fieldKey
            return
        }
        rejectedKey = nil
        let oversized = context.fullText.utf16.count > Self.maxDocumentUnits
        session = Session(key: context.fieldKey,
                          bundleID: bundleID,
                          host: KnownApps.isBrowser(bundleID) ? context.host : nil,
                          startText: oversized ? "" : context.fullText,
                          lastText: context.fullText,
                          lastActivity: Date(),
                          accepted: false,
                          bestSegment: "",
                          context: context,
                          oversized: oversized)
        startIdleTimer()
    }

    private func checkIdle() {
        guard let current = session else { return }
        if Date().timeIntervalSince(current.lastActivity) >= Self.idleTimeout {
            endSession(commit: true)
        }
    }

    private func endSession(commit: Bool) {
        guard let finished = session else { return }
        session = nil
        stopIdleTimer()
        guard commit, !finished.oversized else { return }
        guard finished.lastText.utf16.count <= Self.maxDocumentUnits else { return }

        let prefs = UserPreferences.shared
        guard prefs.recordWritingEnabled else { return }
        guard prefs.recordWritingMode == .everything || finished.accepted else { return }

        let profile = ProfileStore.shared.resolve(bundleID: finished.bundleID, host: finished.host)
        guard ActivationPolicy.allowsRecording(finished.context, profile: profile) else { return }

        var text = Self.insertedSegment(from: finished.startText, to: finished.lastText)
        if finished.bestSegment.count > text.count { text = finished.bestSegment }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > Self.maxSampleCharacters {
            text = String(text.prefix(Self.maxSampleCharacters))
        }
        guard text.count >= Self.minCharacters else { return }
        guard text.filter({ $0.isLetter }).count >= Self.minLetters else { return }
        guard !Self.looksSensitive(text) else {
            QLog.debug(.personalization, "sample skipped (sensitive-looking)")
            return
        }

        let sample = WritingSample(id: UUID().uuidString,
                                   text: text,
                                   bundleID: finished.bundleID,
                                   domain: finished.host,
                                   date: Date(),
                                   script: PersonalizationStore.scriptName(for: text))
        Task.detached(priority: .utility) {
            await PersonalizationStore.shared.add(sample)
        }
    }

    // MARK: - Diff

    /// What was inserted between `old` and `new`: the middle, after dropping
    /// the common prefix and suffix. UTF-16 units, so the offsets match the
    /// values the Accessibility API hands us.
    nonisolated static func insertedSegment(from old: String, to new: String) -> String {
        guard !new.isEmpty else { return "" }
        guard !old.isEmpty else { return new }
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        // Don't cut a surrogate pair in half.
        if prefix > 0, isHighSurrogate(b[prefix - 1]) { prefix -= 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        if suffix > 0, isLowSurrogate(b[b.count - suffix]) { suffix -= 1 }
        let end = b.count - suffix
        guard end > prefix else { return "" }
        return String(decoding: b[prefix..<end], as: UTF16.self)
    }

    private nonisolated static func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    private nonisolated static func isLowSurrogate(_ unit: UInt16) -> Bool {
        (0xDC00...0xDFFF).contains(unit)
    }

    // MARK: - Sensitive content

    /// Drops samples that look like card / account numbers, or that carry an
    /// email address or a URL. Nothing is partially redacted — the whole
    /// sample is skipped.
    nonisolated static func looksSensitive(_ text: String) -> Bool {
        var digitRun = 0
        var digits = 0
        var total = 0
        for ch in text {
            total += 1
            if ch.isNumber {
                digits += 1
                digitRun += 1
                if digitRun >= 12 { return true }
            } else if ch == " " || ch == "-" {
                // A spaced / dashed card number is still a card number.
                continue
            } else {
                digitRun = 0
            }
        }
        if total > 0, Double(digits) / Double(total) > 0.3 { return true }
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let lower = token.lowercased()
            if lower.contains("://") || lower.hasPrefix("www.") { return true }
            if let at = lower.firstIndex(of: "@"),
               at != lower.startIndex, lower[at...].contains(".") { return true }
        }
        return false
    }
}
