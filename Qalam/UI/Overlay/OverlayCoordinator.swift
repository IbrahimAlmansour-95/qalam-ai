import Foundation
import AppKit

/// Owns what is on screen for the current suggestion: the render loop that
/// used to live in `AppDelegate.bindGhostOverlay()` (moved verbatim — same
/// calls, same order, same placement), plus drift following:
///
/// * Full render whenever the suggestion text changes — exactly today's
///   `caretFrame()` → `GhostTextOverlayWindow.update(...)` path.
/// * While a ghost is shown and its text is unchanged, the caret is re-queried
///   now and then. If the window was dragged or the text scrolled, the SAME
///   `update(...)` runs again with the cached text/style and the new caret
///   (after two matching samples, so apps whose caret paths alternate by a
///   few points don't make it jitter). A moved or lost caret also re-reads
///   the field context, so a click elsewhere or a focus change drops the
///   suggestion through the engine instead. A caret that stays lost — and is
///   no longer inside the focused field — hides the ghost. A transient nil
///   keeps it, as before.
/// * Switching apps or Spaces dismisses the suggestion.
/// * When the caret can't be found at all (Electron canvas editors), or the
///   app/site is set to "Mirror bubble", the suggestion is shown in a compact
///   bubble anchored to the focused FIELD instead. Inline placement is never
///   replaced while the caret is readable.
/// * The alternatives list takes the screen while it is open — ghost and
///   bubble are hidden, and come back when it closes.
@MainActor
final class OverlayCoordinator {
    static let shared = OverlayCoordinator()

    enum Presentation: Equatable { case none, inline, mirror }

    private(set) var presentation: Presentation = .none

    /// A ghost or bubble is on screen for a non-empty engine suggestion.
    var isSuggestionVisible: Bool {
        guard !(SuggestionEngine.shared.currentSuggestion?.isEmpty ?? true) else { return false }
        switch presentation {
        case .none:   return false
        case .inline: return GhostTextOverlayWindow.shared.isVisible
        case .mirror: return MirrorBubblePanel.shared.isVisible
        }
    }

    /// Last loop tick at which `isSuggestionVisible` was true.
    private(set) var lastVisibleAt: Date = .distantPast

    private var loopTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    // Last full render — reused by drift updates.
    private var lastText = ""
    private var lastCaret: CGRect?
    private var lastStyle = AccessibilityMonitor.CaretStyle(fontName: nil, pointSize: 14, rgba: nil)
    private var lastHint: GhostStyleHint = .completion
    private var lastRTL = false
    private var lastPlaceLeft = false
    /// Field frame the mirror bubble is anchored to.
    private var lastField: CGRect?

    // Mirror-bubble hysteresis: the bubble appears only after the caret came
    // back nil twice in a row for the same app, so an app whose caret query
    // misses once keeps its inline ghost.
    private var nilCaretStreak = 0
    private var nilCaretStreakPID: pid_t?
    /// A full render found no caret: sample once more on the next tick.
    private var recheckNextTick = false
    private var tickCount = 0

    // Drift state.
    /// Earliest uptime for the next drift check (≈240 ms apart, stretched
    /// for apps whose caret query is slow so the main thread stays free).
    private var nextDriftCheckAt: TimeInterval = 0
    private var driftNilStreak = 0
    /// A moved caret seen once; applied only if the next check agrees.
    private var pendingDriftCaret: CGRect?
    /// Uptime of the last context re-read requested by a drift check.
    private var lastDriftPumpAt: TimeInterval = 0

    private static let tickNanoseconds: UInt64 = 60_000_000
    private static let driftInterval: TimeInterval = 0.24
    /// Drift check cost × this = minimum gap to the next check.
    private static let driftCostMultiplier: TimeInterval = 8
    private static let driftMoveThreshold: CGFloat = 2
    private static let driftMatchTolerance: CGFloat = 1
    private static let driftNilSamplesToHide = 3
    /// Drift re-reads are rare events (a click, a focus change); never more
    /// often than this, whatever an app's caret does.
    private static let driftPumpMinInterval: TimeInterval = 1.5
    /// Nil caret samples needed before the mirror bubble takes over.
    private static let mirrorNilSamples = 2
    /// Nil field samples before an anchored bubble is hidden.
    private static let mirrorNilSamplesToHide = 2
    /// Ticks between field-button evaluations (≈240 ms).
    private static let fieldButtonEveryTicks = 4
    /// Longest "typo → fix" the ghost shows before falling back to the fix
    /// alone (a long sentence rewrite would cover the user's own text).
    private static let arrowMaxChars = 60
    /// Quiet typing needed before the alternatives list opens by itself.
    private static let autoShowIdleSeconds: TimeInterval = 1.5

    /// The alternatives list is covering the ghost / bubble.
    private var listSuppressed = false
    /// Suggestion text the list already opened for, so it opens once.
    private var autoShownForText = ""

    private init() {}

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: OverlayCoordinator.tickNanoseconds)
            }
        }

        // Context jumps: whatever was suggested belongs to the previous app /
        // Space. (Queue `.main` → delivered on the main thread.)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    // The list belongs to the field that was focused a moment
                    // ago — it must never hang over the new app.
                    AlternativesProvider.shared.close()
                    SuggestionEngine.shared.dismiss()
                }
            })
        }
    }

    /// Hides every overlay surface now. A suggestion still held re-renders
    /// on a later tick if it is still valid.
    func hideAll() {
        AlternativesProvider.shared.close()
        hideSurfaces()
        FieldButtonPanel.shared.hide()
        resetRenderState()
    }

    /// Forces a full re-render on the next tick (e.g. a setting changed).
    func invalidate() {
        lastText = ""
    }

    // MARK: - Loop

    private func tick() {
        tickCount &+= 1
        // Secure Input: nothing is shown. Reset `lastText` so a suggestion
        // still held afterwards renders again.
        if SecureInputMonitor.shared.isActive {
            if !lastText.isEmpty {
                hideSurfaces()
                resetRenderState()
            }
            FieldButtonPanel.shared.hide()
            return
        }
        // The alternatives list replaces the ghost / bubble while it is up —
        // never two suggestion surfaces at once.
        if AlternativesPanel.shared.isVisible {
            if presentation != .none {
                hideSurfaces()
                presentation = .none
                lastCaret = nil
                lastField = nil
                resetDrift(nextCheckIn: 0)
            }
            listSuppressed = true
            FieldButtonPanel.shared.hide()
            AlternativesProvider.shared.revalidate()
            return
        }
        if listSuppressed {
            // List closed: render the suggestion it was covering again.
            listSuppressed = false
            lastText = ""
        }
        let suggestion = SuggestionEngine.shared.currentSuggestion
        let text = Self.displayText(for: suggestion)
        let backedOff = AXGuard.isBackedOff(AXGuard.frontmostPID())
        if text != lastText, !text.isEmpty, backedOff {
            // Frontmost app tripped the slow-AX breaker: no AX calls.
            // Hide (once) and reset `lastText` so the render retries as soon
            // as the breaker clears.
            if !lastText.isEmpty {
                hideSurfaces()
                resetRenderState()
            }
        } else if text != lastText {
            lastText = text
            if text.isEmpty {
                hideSurfaces()
                resetRenderState()
            } else {
                render(text: text, suggestion: suggestion)
            }
        } else if presentation == .inline {
            checkDrift()
        } else if presentation == .mirror {
            checkMirrorDrift()
        } else if recheckNextTick, !text.isEmpty, !backedOff {
            // Second caret sample, 60 ms after the first: two misses in a row
            // are what turns the mirror bubble on.
            render(text: text, suggestion: suggestion)
        }

        if isSuggestionVisible {
            lastVisibleAt = Date()
        }
        evaluateAutoShow(text: text)
        if tickCount % Self.fieldButtonEveryTicks == 0 {
            FieldButtonPanel.shared.update(context: AccessibilityMonitor.shared.currentContext)
        }
    }

    /// "Show alternatives automatically after a pause" (off by default): once
    /// per suggestion, and only while one is really on screen.
    private func evaluateAutoShow(text: String) {
        guard UserPreferences.shared.alternativesAutoShow else { return }
        guard !text.isEmpty else {
            autoShownForText = ""
            return
        }
        guard isSuggestionVisible, autoShownForText != text else { return }
        guard Date().timeIntervalSince(KeystrokeInterceptor.shared.lastKeyDownAt)
                >= Self.autoShowIdleSeconds else { return }
        autoShownForText = text
        AlternativesProvider.shared.show(auto: true)
    }

    /// What the ghost / bubble draws for a suggestion. Everything except a
    /// correction in "typo → fix" style is the suggestion's own text.
    private static func displayText(for suggestion: SuggestionResult?) -> String {
        guard let suggestion, !suggestion.isEmpty else { return "" }
        guard case .correction(let original, let replacement, _, _, _) = suggestion.kind,
              UserPreferences.shared.autocorrectStyle == .arrow,
              original.count + replacement.count <= arrowMaxChars
        else { return suggestion.text }
        // Arabic text is laid out right-to-left, so the arrow has to point the
        // other way for the typo to still read as coming BEFORE the fix.
        let arrow = Script.dominant(in: replacement) == .arabic ? " ← " : " → "
        return original + arrow + replacement
    }

    /// Full render of `text`: inline at the caret when we can find it, else
    /// the mirror bubble (or nothing, per the user's setting).
    private func render(text: String, suggestion: SuggestionResult?) {
        recheckNextTick = false
        let pid = AXGuard.frontmostPID()
        if pid != nilCaretStreakPID {
            // Hysteresis is per app: an Electron app's misses must not make
            // the next app show a bubble on its first miss.
            nilCaretStreakPID = pid
            nilCaretStreak = 0
        }
        let hint = OverlayCoordinator.hint(for: suggestion)
        // Two directions: how the suggestion TEXT reads (its own script) vs
        // which SIDE to place the box. The box follows the line's BASE
        // direction (its first strong character), so on an English-started
        // line an Arabic suggestion extends right into the empty space after
        // the cursor — not left over the English already there.
        let textRTL = OverlayCoordinator.isRTLText(text)
        let placeLeft = OverlayCoordinator.baseDirectionRTL(suggestion?.basedOnContext ?? "")

        // The user asked for the bubble in this app / on this site: don't even
        // query the caret.
        if ProfileStore.shared.activeResolved.displayMode == .mirror {
            let field = AXGuard.measure(pid: pid) { AccessibilityMonitor.shared.focusedFrame() }
            if let field {
                showMirror(text: text, hint: hint, field: field, isRTL: textRTL)
            } else {
                hideSurfaces()
                presentation = .none
                lastCaret = nil
                lastField = nil
            }
            return
        }

        if let (caret, style) = AXGuard.measure(pid: pid, {
            // Same calls, same order as before — only timed.
            AccessibilityMonitor.shared.caretFrame().map {
                ($0, AccessibilityMonitor.shared.caretStyle())
            }
        }) {
            nilCaretStreak = 0
            MirrorBubblePanel.shared.hide()
            lastField = nil
            GhostTextOverlayWindow.shared.update(
                text: text, hint: hint, style: style, caret: caret,
                isRTL: textRTL, placeLeft: placeLeft)
            presentation = .inline
            lastCaret = caret
            lastStyle = style
            lastHint = hint
            lastRTL = textRTL
            lastPlaceLeft = placeLeft
            resetDrift(nextCheckIn: Self.driftInterval)
            return
        }

        // No trustworthy caret (e.g. Electron canvas editors) — never draw
        // inline at a guessed location.
        nilCaretStreak += 1
        if UserPreferences.shared.caretUnavailableBehavior == .bubble,
           nilCaretStreak >= Self.mirrorNilSamples,
           let field = AXGuard.measure(pid: pid, { AccessibilityMonitor.shared.focusedFrame() }) {
            showMirror(text: text, hint: hint, field: field, isRTL: textRTL)
            return
        }
        hideSurfaces()
        presentation = .none
        lastCaret = nil
        lastField = nil
        if UserPreferences.shared.caretUnavailableBehavior == .bubble,
           nilCaretStreak < Self.mirrorNilSamples {
            recheckNextTick = true
        }
    }

    private func showMirror(text: String, hint: GhostStyleHint, field: CGRect, isRTL: Bool) {
        // The two surfaces are never on screen together.
        GhostTextOverlayWindow.shared.hide()
        MirrorBubblePanel.shared.show(text: text, hint: hint, fieldFrame: field, isRTL: isRTL)
        presentation = .mirror
        lastField = field
        lastCaret = nil
        lastHint = hint
        lastRTL = isRTL
        resetDrift(nextCheckIn: Self.driftInterval)
    }

    private func hideSurfaces() {
        GhostTextOverlayWindow.shared.hide()
        MirrorBubblePanel.shared.hide()
    }

    /// Text unchanged, ghost shown: follow the caret if it moved (window drag,
    /// scroll), hide if it is gone for good. Never changes placement math —
    /// it re-runs the same `update(...)` with the new caret.
    private func checkDrift() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextDriftCheckAt, let previous = lastCaret, !lastText.isEmpty else { return }
        let pid = AXGuard.frontmostPID()
        // Slow-AX breaker tripped: leave the ghost as it is.
        guard !AXGuard.isBackedOff(pid) else {
            nextDriftCheckAt = now + Self.driftInterval
            return
        }

        // Space checks by what this one cost (caret query + any re-read), so an
        // app with slow AX replies never keeps the main thread busy.
        defer {
            let end = ProcessInfo.processInfo.systemUptime
            nextDriftCheckAt = end + max(Self.driftInterval, (end - now) * Self.driftCostMultiplier)
        }

        let caret = AXGuard.measure(pid: pid) { AccessibilityMonitor.shared.caretFrame() }

        guard let caret else {
            // A transient nil (common in some apps) keeps the ghost where it
            // is. Only a caret lost for several checks AND no longer inside
            // the focused field hides it.
            pendingDriftCaret = nil
            driftNilStreak += 1
            guard driftNilStreak >= Self.driftNilSamplesToHide else { return }
            // Focus may have moved to another element (window closed, list
            // clicked): a re-read hands the engine the new context, which
            // drops the suggestion. Same field → same context → no-op.
            pumpForDrift()
            let field = AXGuard.measure(pid: pid) { AccessibilityMonitor.shared.focusedFrame() }
            let mid = CGPoint(x: previous.midX, y: previous.midY)
            if field == nil || !(field?.insetBy(dx: -4, dy: -4).contains(mid) ?? false) {
                hideForDrift()
            } else {
                driftNilStreak = 0
            }
            return
        }
        driftNilStreak = 0

        let moved = abs(caret.minX - previous.minX) > Self.driftMoveThreshold
            || abs(caret.minY - previous.minY) > Self.driftMoveThreshold
            || abs(caret.height - previous.height) > Self.driftMoveThreshold
        guard moved else {
            pendingDriftCaret = nil
            return
        }
        guard let pending = pendingDriftCaret, Self.sameCaret(pending, caret) else {
            // First sighting — confirm on the next check before moving. Also
            // re-read the field: if the caret moved because the user clicked
            // elsewhere (text before it changed), the engine drops this
            // suggestion before the next check instead of the ghost following
            // to a spot it wasn't written for. A pure scroll / window drag
            // reads the same context and changes nothing.
            pendingDriftCaret = caret
            pumpForDrift()
            return
        }
        pendingDriftCaret = nil
        // The re-read above cleared or replaced the suggestion: the text-change
        // path owns the next render.
        guard Self.displayText(for: SuggestionEngine.shared.currentSuggestion) == lastText else { return }

        // Scrolled off every screen: nothing sensible to point at.
        let mid = CGPoint(x: caret.midX, y: caret.midY)
        guard NSScreen.screens.contains(where: { $0.frame.contains(mid) }) else {
            hideForDrift()
            return
        }
        GhostTextOverlayWindow.shared.update(
            text: lastText, hint: lastHint, style: lastStyle, caret: caret,
            isRTL: lastRTL, placeLeft: lastPlaceLeft)
        lastCaret = caret
        QLog.debug(.overlay, "ghost followed caret drift")
    }

    /// Same idea for the bubble: follow the FIELD (window dragged, layout
    /// changed) and hide when the field is gone.
    private func checkMirrorDrift() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextDriftCheckAt, let previous = lastField, !lastText.isEmpty else { return }
        let pid = AXGuard.frontmostPID()
        guard !AXGuard.isBackedOff(pid) else {
            nextDriftCheckAt = now + Self.driftInterval
            return
        }
        defer {
            let end = ProcessInfo.processInfo.systemUptime
            nextDriftCheckAt = end + max(Self.driftInterval, (end - now) * Self.driftCostMultiplier)
        }

        let field = AXGuard.measure(pid: pid) { AccessibilityMonitor.shared.focusedFrame() }
        guard let field else {
            // One missed read doesn't mean focus left the field.
            driftNilStreak += 1
            guard driftNilStreak >= Self.mirrorNilSamplesToHide else { return }
            pumpForDrift()
            MirrorBubblePanel.shared.hide()
            presentation = .none
            lastField = nil
            resetDrift(nextCheckIn: 0)
            QLog.debug(.overlay, "mirror bubble hidden: field lost")
            return
        }
        driftNilStreak = 0

        let moved = abs(field.minX - previous.minX) > Self.driftMoveThreshold
            || abs(field.minY - previous.minY) > Self.driftMoveThreshold
            || abs(field.width - previous.width) > Self.driftMoveThreshold
            || abs(field.height - previous.height) > Self.driftMoveThreshold
        guard moved else { return }
        MirrorBubblePanel.shared.show(text: lastText, hint: lastHint,
                                      fieldFrame: field, isRTL: lastRTL)
        lastField = field
        QLog.debug(.overlay, "mirror bubble followed field")
    }

    private func pumpForDrift() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDriftPumpAt >= Self.driftPumpMinInterval else { return }
        lastDriftPumpAt = now
        AccessibilityMonitor.shared.pump()
    }

    /// Hides for a lost caret but keeps `lastText`, so the same suggestion is
    /// not re-rendered at a stale spot on the next tick. New text renders again.
    private func hideForDrift() {
        GhostTextOverlayWindow.shared.hide()
        presentation = .none
        lastCaret = nil
        resetDrift(nextCheckIn: 0)
        QLog.debug(.overlay, "ghost hidden: caret lost")
    }

    private func resetRenderState() {
        lastText = ""
        presentation = .none
        lastCaret = nil
        lastField = nil
        recheckNextTick = false
        resetDrift(nextCheckIn: 0)
    }

    private func resetDrift(nextCheckIn delay: TimeInterval) {
        driftNilStreak = 0
        pendingDriftCaret = nil
        nextDriftCheckAt = ProcessInfo.processInfo.systemUptime + delay
    }

    private static func sameCaret(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= driftMatchTolerance
            && abs(a.minY - b.minY) <= driftMatchTolerance
            && abs(a.height - b.height) <= driftMatchTolerance
    }

    // MARK: - Helpers (moved verbatim from AppDelegate)

    /// True when the suggestion text is predominantly Arabic (RTL) — drives the
    /// suggestion text's layout direction.
    private static func isRTLText(_ text: String) -> Bool {
        Script.dominant(in: text) == .arabic
    }

    /// Base (paragraph) direction of the cursor's line, from its FIRST strong
    /// directional character — this is what determines where the cursor visually
    /// advances. Used to choose which side to place the ghost so it goes into
    /// empty space, not over existing text, on mixed LTR/RTL lines.
    private static func baseDirectionRTL(_ context: String) -> Bool {
        let line = context.split(whereSeparator: { $0.isNewline }).last.map(String.init) ?? context
        return Script.firstStrong(in: line) == .arabic
    }

    private static func hint(for suggestion: SuggestionResult?) -> GhostStyleHint {
        guard let kind = suggestion?.kind else { return .completion }
        switch kind {
        case .llm: return .completion
        case .snippet: return .snippet
        case .emoji:   return .snippet
        case .correction(_, _, _, _, let issueKind):
            return issueKind == .spelling ? .spellingFix : .grammarFix
        }
    }
}
