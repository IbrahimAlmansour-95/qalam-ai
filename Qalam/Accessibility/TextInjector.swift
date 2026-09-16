import Foundation
import AppKit
import ApplicationServices

/// Injects text into the focused element. Tries the AX value path first, falls
/// back to synthetic keystrokes via CGEvent.
@MainActor
final class TextInjector {
    static let shared = TextInjector()

    /// Stamped into `.eventSourceUserData` of every key event we post, so the
    /// keystroke tap can recognise (and never act on) our own typing.
    nonisolated static let syntheticEventTag: Int64 = 0x514C4D31   // "QLM1"

    /// Most apps accept ~20 UTF-16 units per unicode key event; stay below.
    private static let maxUnitsPerEvent = 16
    private static let backspaceKey: CGKeyCode = 0x33   // virtual key for Delete (backspace)

    private init() {}

    func injectWord(_ word: String, withTrailingSpace: Bool = true) {
        let payload = withTrailingSpace ? word + " " : word
        if injectViaAX(payload) { return }
        injectViaCGEvent(payload)
    }

    /// Deletes `deleteCount` backspace-presses before the caret, then types
    /// `text` — as ONE ordered stream of key events (same source, same tap).
    ///
    /// Never mixes in AX: an AX insert goes straight to the app, while posted
    /// backspaces still have to pass the event taps (ours runs on this very
    /// main thread), so the insert would land first and the backspaces would
    /// then eat the end of the replacement.
    func replaceBeforeCursor(deleteCount: Int, with text: String) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        for _ in 0..<max(0, deleteCount) {
            post(virtualKey: Self.backspaceKey, unicode: nil, source: src)
        }
        typeText(text, source: src)
    }

    /// Backspace presses needed to delete `text` in a typical host app: one
    /// per Character (an emoji or composed sequence goes in one press), plus
    /// one per Arabic combining mark — AppKit and Chromium delete harakat one
    /// keypress at a time, so "كَتَبَ" takes 6, not 3.
    nonisolated static func backspaceCount<S: StringProtocol>(for text: S) -> Int {
        var count = 0
        for character in text {
            count += 1
            for scalar in character.unicodeScalars where isArabicCombiningMark(scalar) {
                count += 1
            }
        }
        return count
    }

    private nonisolated static func isArabicCombiningMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x064B...0x065F, 0x0670, 0x06D6...0x06ED:
            // The 06D6–06ED block also holds a few non-mark signs.
            return scalar.properties.generalCategory == .nonspacingMark
        default:
            return false
        }
    }

    /// Returns true if AX injection succeeded. Skipped (→ CGEvent fallback)
    /// while the frontmost app has tripped the slow-AX breaker.
    private func injectViaAX(_ text: String) -> Bool {
        let pid = AXGuard.frontmostPID()
        guard !AXGuard.isBackedOff(pid) else { return false }
        return AXGuard.measure(pid: pid) { setSelectedTextViaAX(text) }
    }

    private func setSelectedTextViaAX(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let elementUnwrapped = focused,
              CFGetTypeID(elementUnwrapped as CFTypeRef) == AXUIElementGetTypeID()
        else { return false }
        let element = unsafeDowncast(elementUnwrapped, to: AXUIElement.self)

        var rangeRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef {
            let _ = rangeValue
            let started = ProcessInfo.processInfo.systemUptime
            let err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            if err == .success { return true }
            // A set that hit the messaging timeout was most likely delivered —
            // the app is just slow to reply and will still insert the text.
            // Typing it again via CGEvent would insert it twice, so treat it
            // as done.
            if err == .cannotComplete,
               ProcessInfo.processInfo.systemUptime - started >= Double(AXGuard.messagingTimeout) * 0.9 {
                return true
            }
        }
        return false
    }

    private func injectViaCGEvent(_ text: String) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        typeText(text, source: src)
    }

    /// Types `text` as unicode key events, split at Character boundaries into
    /// chunks of ≤ `maxUnitsPerEvent` UTF-16 units (longer strings get
    /// silently truncated by many apps).
    private func typeText(_ text: String, source: CGEventSource) {
        var chunk: [UniChar] = []
        for character in text {
            let units = Array(character.utf16)
            if !chunk.isEmpty, chunk.count + units.count > Self.maxUnitsPerEvent {
                post(virtualKey: 0, unicode: chunk, source: source)
                chunk.removeAll(keepingCapacity: true)
            }
            chunk.append(contentsOf: units)
        }
        if !chunk.isEmpty {
            post(virtualKey: 0, unicode: chunk, source: source)
        }
    }

    /// Posts a key down + up. Modifier flags are cleared: the user may still
    /// be holding ⇧ from ⇧Tab, and ⇧/⌥-modified Delete or unicode events are
    /// interpreted differently by some apps (Terminal, Electron).
    private func post(virtualKey: CGKeyCode, unicode: [UniChar]?, source: CGEventSource) {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown)
            else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
            if let unicode {
                unicode.withUnsafeBufferPointer { buf in
                    guard let base = buf.baseAddress else { return }
                    event.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
                }
            }
            event.post(tap: .cghidEventTap)
        }
    }
}
