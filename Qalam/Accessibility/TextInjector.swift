import Foundation
import AppKit
import ApplicationServices

/// Injects text into the focused element. Tries the AX value path first, falls
/// back to synthetic keystrokes via CGEvent.
@MainActor
final class TextInjector {
    static let shared = TextInjector()

    private init() {}

    func injectWord(_ word: String, withTrailingSpace: Bool = true) {
        let payload = withTrailingSpace ? word + " " : word
        if injectViaAX(payload) { return }
        injectViaCGEvent(payload)
    }

    /// Sends `count` backspace key events to delete the previous `count` characters.
    func deleteBackwards(count: Int) {
        guard count > 0, let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let backspaceKey: CGKeyCode = 0x33   // virtual key for Delete (backspace)
        for _ in 0..<count {
            if let down = CGEvent(keyboardEventSource: src, virtualKey: backspaceKey, keyDown: true) {
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: backspaceKey, keyDown: false) {
                up.post(tap: .cghidEventTap)
            }
        }
    }

    /// Returns true if AX injection succeeded.
    private func injectViaAX(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let elementUnwrapped = focused
        else { return false }
        let element = elementUnwrapped as! AXUIElement

        var rangeRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef {
            let _ = rangeValue
            let err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            if err == .success { return true }
        }
        return false
    }

    private func injectViaCGEvent(_ text: String) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                up.post(tap: .cghidEventTap)
            }
        }
    }
}
