import Foundation
import AppKit
import CoreGraphics

/// Installs a CGEventTap to:
///   * intercept Tab/⇧Tab/Esc when a suggestion is active
///   * trigger AccessibilityMonitor.pump() on every other keystroke
@MainActor
final class KeystrokeInterceptor {
    static let shared = KeystrokeInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// When the user last pressed a key that reached the app (T5 field button,
    /// T7 auto-show).
    private(set) var lastKeyDownAt: Date = .distantPast

    /// How long after the ghost was last on screen its keys still act on it.
    private static let ghostGraceSeconds: TimeInterval = 0.35

    private init() {}

    func install() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: KeystrokeInterceptor.tapCallback,
            userInfo: context
        ) else {
            QLog.error(.input, "failed to create CGEventTap — needs Accessibility permission")
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func uninstall() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - C callback

    private static let tapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<KeystrokeInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
        return interceptor.handle(proxy: proxy, type: type, event: event)
    }

    /// Runs on the main thread for EVERY key event system-wide, so it only
    /// decides swallow / pass from cheap in-memory state. Anything that talks
    /// to Accessibility or posts events (accept, dismiss, rewrite) is queued
    /// with `DispatchQueue.main.async` and runs right after the callback
    /// returns — FIFO, so rapid presses keep their order. A slow target app
    /// can then never stall the tap itself (which macOS would disable).
    ///
    /// Every shortcut matches a PHYSICAL key plus EXACT modifiers, so it works
    /// on any keyboard layout and never eats a key combination it doesn't own
    /// (⌃⇥, ⌘→ and an unmodified key above Tab — ذ on the Arabic layout — all
    /// pass through). Keys that act on a suggestion are swallowed only while
    /// one is really on screen.
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            QLog.notice(.input, "event tap re-enabled (\(type == .tapDisabledByTimeout ? "timeout" : "userInput"))")
            return Unmanaged.passUnretained(event)
        }
        // Our own injected typing (accept, correction, snippet): never a
        // shortcut. One pump once the burst is over, instead of one per event.
        if event.getIntegerValueField(.eventSourceUserData) == TextInjector.syntheticEventTag {
            if type == .keyDown { scheduleSyntheticPump() }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let mods = KeyMods(event.flags)
        let prefs = UserPreferences.shared

        // ── Global shortcuts (no suggestion needed) ──────────────────────────

        // ⌘⇧Space — pause / resume everywhere.
        if keyCode == KeyCode.space, mods == [.command, .shift], prefs.shortcutPauseEnabled,
           !KnownApps.isShortcutReservedEditor(Self.frontmostBundleID()) {
            runAfterCallback { KeystrokeInterceptor.shared.toggleGlobalPause() }
            return nil   // consume
        }
        // ⌃⌥⌘ + key above Tab — pause the frontmost app for 10 minutes.
        if KeyCode.isAboveTab(keyCode), mods == [.control, .option, .command],
           prefs.shortcutAppToggleEnabled {
            runAfterCallback { KeystrokeInterceptor.shared.toggleFrontmostAppPause() }
            return nil   // consume
        }
        // ⌃ + key above Tab — suggest now. ⌃` toggles the terminal in VS Code,
        // Cursor, Windsurf and Zed, so it passes through there unless that
        // editor is set to "Force only" (where it's the only way to ask).
        if KeyCode.isAboveTab(keyCode), mods == [.control], prefs.shortcutForceActivateEnabled,
           Self.forceShortcutAllowedInFrontmostApp() {
            runAfterCallback { KeystrokeInterceptor.shared.forceActivate() }
            return nil   // consume
        }
        // ⌃⌥R — tone-rewrite the current selection.
        if keyCode == KeyCode.r, mods == [.control, .option] {
            runAfterCallback { SelectionRewriter.shared.begin() }
            return nil   // consume
        }

        // ── The alternatives list owns 1–5 and Esc while it is open ─────────

        if AlternativesPanel.shared.isVisible {
            // Only digits that name an option on screen are taken — while the
            // list is still loading, numbers reach the app as usual.
            let optionCount = AlternativesProvider.shared.options.count
            if let option = KeyCode.digits[keyCode], mods == [], option <= optionCount {
                runAfterCallback { AlternativesProvider.shared.insert(index: option) }
                return nil   // consume
            }
            if keyCode == KeyCode.escape, mods.hasNoCommandControlOption {
                runAfterCallback { AlternativesProvider.shared.close() }
                return nil   // consume
            }
            // The accept key takes the first option, like it takes the ghost.
            if optionCount > 0, acceptKeyCodes().contains(keyCode), mods.hasNoCommandControlOption {
                runAfterCallback { AlternativesProvider.shared.insert(index: 1) }
                return nil   // consume
            }
            // Anything else closes the list and reaches the app as usual.
            runAfterCallback { AlternativesProvider.shared.close() }
        }

        // ── Keys that act on a visible suggestion ───────────────────────────

        let ghostVisible = isGhostVisible()
        if ghostVisible {
            // ⌥⇥ types a real Tab instead of accepting.
            if keyCode == KeyCode.tab, mods == [.option] {
                return passThrough(event)
            }
            // Accept: the configured key, optionally with ⇧ for the whole
            // suggestion. Apps set to "Tab passes through" use → instead.
            if acceptKeyCodes().contains(keyCode), mods.isSubset(of: [.shift]) {
                let all = mods.contains(.shift)
                runAfterCallback {
                    if all {
                        _ = SuggestionEngine.shared.acceptAll()
                    } else {
                        _ = SuggestionEngine.shared.acceptNextWord()
                    }
                }
                return nil   // consume
            }
            // Opt-in: the key above Tab accepts the whole suggestion. It is
            // never swallowed unmodified unless the user asked for this — on
            // the Arabic layout it types ذ.
            if KeyCode.isAboveTab(keyCode), mods == [], prefs.acceptAllKeyAboveTab {
                runAfterCallback { _ = SuggestionEngine.shared.acceptAll() }
                return nil   // consume
            }
            // Esc.
            if keyCode == KeyCode.escape, mods.hasNoCommandControlOption {
                switch prefs.escBehavior {
                case .dismissOnly:
                    runAfterCallback { SuggestionEngine.shared.dismiss() }
                    return nil   // consume
                case .dismissAndPause:
                    runAfterCallback { SuggestionEngine.shared.dismissAndPauseField() }
                    return nil   // consume
                case .passThrough:
                    runAfterCallback { SuggestionEngine.shared.dismiss() }
                    return passThrough(event)
                }
            }
            // ⌥] cycles to an alternative completion.
            if keyCode == KeyCode.rightBracket, mods == [.option] {
                runAfterCallback { SuggestionEngine.shared.cycleAlternative() }
                return nil   // consume
            }
            // ⌥\ lists other words that could come next. Only while a
            // suggestion is showing, so typing « (⌥\ on some layouts) is
            // otherwise untouched.
            if keyCode == KeyCode.backslash, mods == [.option], prefs.shortcutAlternativesEnabled {
                runAfterCallback { AlternativesProvider.shared.show() }
                return nil   // consume
            }
        }

        return passThrough(event)
    }

    /// Pass the key to the app and re-read the field once it has landed.
    private func passThrough(_ event: CGEvent) -> Unmanaged<CGEvent> {
        lastKeyDownAt = Date()
        // The field badge gets out of the way while the user types (no-op
        // when it isn't showing, which is the default).
        FieldButtonPanel.shared.noteTyping()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
            AccessibilityMonitor.shared.pump()
        }
        return Unmanaged.passUnretained(event)
    }

    /// Queues an action for the next main-queue turn: the tap callback itself
    /// must never do Accessibility work or post events.
    private func runAfterCallback(_ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                action()
            }
        }
    }

    /// A suggestion is really on screen. The short grace after it was last
    /// visible keeps rapid Tab-Tab-Tab accepting word by word: the re-render
    /// right after an accept can miss the caret for a frame, and without the
    /// grace the next Tab would be typed into the document.
    private func isGhostVisible() -> Bool {
        let overlay = OverlayCoordinator.shared
        if overlay.isSuggestionVisible { return true }
        let suggestion = SuggestionEngine.shared.currentSuggestion
        guard let suggestion, !suggestion.isEmpty else { return false }
        return Date().timeIntervalSince(overlay.lastVisibleAt) < Self.ghostGraceSeconds
    }

    /// Which key codes accept: → when the user picked it, or when this app is
    /// set to let Tab through.
    private func acceptKeyCodes() -> [Int64] {
        if UserPreferences.shared.acceptWordKey == "rightArrow" { return [KeyCode.rightArrow] }
        return ProfileStore.shared.activeResolved.tabAcceptEnabled ? [KeyCode.tab] : [KeyCode.rightArrow]
    }

    // MARK: - Shortcut actions

    private func toggleGlobalPause() {
        let prefs = UserPreferences.shared
        // Toggles what the user sees: "suggesting" ↔ "paused". Resuming also
        // ends a snooze, which is what "resume" means to them.
        let wasActive = prefs.isEnabled && !prefs.isSnoozed
        if wasActive {
            prefs.isEnabled = false
            SuggestionEngine.shared.dismiss()
        } else {
            prefs.isEnabled = true
            if prefs.isSnoozed { prefs.snoozeUntil = nil }
        }
        let resumed = !wasActive
        QLog.notice(.input, "global pause shortcut → \(resumed ? "resumed" : "paused")")
        MenuBarController.shared.refreshStatusAppearance()
        StatusToastPanel.shared.show(L.t(resumed ? .toastResumed : .toastPaused),
                                     icon: resumed ? "play.circle" : "pause.circle")
    }

    private func toggleFrontmostAppPause() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, bundleID != Constants.bundleID
        else { return }
        let name = app.localizedName ?? bundleID
        let paused = TemporaryPauseStore.shared.toggle(bundleID: bundleID)
        if paused { SuggestionEngine.shared.dismiss() }
        MenuBarController.shared.refreshStatusAppearance()
        StatusToastPanel.shared.show(
            String(format: L.t(paused ? .toastPausedAppFmt : .toastResumedAppFmt), name),
            icon: paused ? "pause.circle" : "play.circle")
    }

    /// Runs the force-activate shortcut and explains a refusal, since nothing
    /// visible would happen otherwise.
    private func forceActivate() {
        guard let decision = SuggestionEngine.shared.forceActivate() else { return }
        switch decision {
        case .allow, .idle:
            break
        case .blocked(.noField):
            StatusToastPanel.shared.show(L.t(.toastNoField), icon: "text.cursor")
        case .blocked(.globallyDisabled), .blocked(.snoozed):
            StatusToastPanel.shared.show(L.t(.toastPaused), icon: "pause.circle")
        case .blocked(.secureInput):
            break
        case .blocked(.secureField), .blocked(.appOff), .blocked(.appTemporarilyPaused):
            StatusToastPanel.shared.show(L.t(.toastForceBlocked), icon: "nosign")
        }
    }

    // MARK: - Frontmost app (no AX, no IPC)

    private static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// ⌃ + key above Tab is left to VS Code-family editors (it toggles their
    /// terminal) unless the user set that editor to "Force only".
    private static func forceShortcutAllowedInFrontmostApp() -> Bool {
        let bundleID = frontmostBundleID()
        guard KnownApps.isShortcutReservedEditor(bundleID) else { return true }
        let store = ProfileStore.shared
        let resolved = store.activeResolved.bundleID == bundleID
            ? store.activeResolved
            : store.resolve(bundleID: bundleID, host: nil)
        return resolved.activation == .forceOnly
    }

    /// Bumped per synthetic key event; only the latest scheduled pump runs.
    private var syntheticPumpGeneration = 0

    private func scheduleSyntheticPump() {
        syntheticPumpGeneration &+= 1
        let generation = syntheticPumpGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            MainActor.assumeIsolated {
                guard KeystrokeInterceptor.shared.syntheticPumpGeneration == generation else { return }
                AccessibilityMonitor.shared.pump()
            }
        }
    }
}
