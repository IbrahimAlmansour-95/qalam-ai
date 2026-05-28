import Foundation
import AppKit
import ApplicationServices

struct TextContext: Sendable, Equatable {
    let appBundleID: String?
    let textBeforeCursor: String
    let wordBeingTyped: String
    let cursorIndex: Int
    let fullText: String

    static let empty = TextContext(appBundleID: nil, textBeforeCursor: "", wordBeingTyped: "", cursorIndex: 0, fullText: "")
}

/// Polls the focused UI element via the AX API to extract typing context.
/// Avoids per-keystroke AX observers, which are flaky across apps; instead
/// uses a short polling cycle triggered by KeystrokeInterceptor (via `pump()`).
@MainActor
final class AccessibilityMonitor {
    static let shared = AccessibilityMonitor()

    private var continuations: [UUID: AsyncStream<TextContext>.Continuation] = [:]
    private var lastContext: TextContext = .empty

    private init() {}

    // MARK: - Permission

    @discardableResult
    func checkPermission(prompt: Bool = false) -> Bool {
        // kAXTrustedCheckOptionPrompt is a non-const global CFStringRef which
        // Swift 6 strict concurrency rejects. Use the raw string instead.
        let options = ["AXTrustedCheckOptionPrompt" as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Streaming

    func contextStream() -> AsyncStream<TextContext> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Sample the focused element's text + caret. Call this on every keystroke.
    func pump() {
        let ctx = currentTextContext()
        guard ctx != lastContext else { return }
        lastContext = ctx
        for c in continuations.values {
            c.yield(ctx)
        }
    }

    // MARK: - AX extraction

    private func currentTextContext() -> TextContext {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let elementUnwrapped = focused else { return .empty }
        // CFTypeID check is safer than direct cast under Swift 6.
        let element = elementUnwrapped as! AXUIElement

        // Skip password fields.
        var roleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String, role == "AXSecureTextField" {
            return .empty
        }
        var subroleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
           let subrole = subroleValue as? String, subrole == "AXSecureTextField" {
            return .empty
        }

        // Pull text value.
        var valueRef: AnyObject?
        let text: String
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let s = valueRef as? String {
            text = s
        } else {
            return .empty
        }

        // Pull selected range for caret position.
        var rangeRef: AnyObject?
        var cursorIdx = text.count
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef {
            // It's an AXValueRef wrapping a CFRange.
            // Use AXValueGetValue.
            let axVal = rangeValue as! AXValue
            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(axVal, .cfRange, &range) {
                cursorIdx = max(0, min(text.count, range.location + range.length))
            }
        }

        // Slice prefix safely.
        let index = text.index(text.startIndex, offsetBy: cursorIdx, limitedBy: text.endIndex) ?? text.endIndex
        var prefix = String(text[..<index])
        if prefix.count > Constants.Suggestion.maxContextChars {
            let dropCount = prefix.count - Constants.Suggestion.maxContextChars
            prefix = String(prefix.dropFirst(dropCount))
        }

        let lastWord = AccessibilityMonitor.lastWord(in: prefix)
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        return TextContext(
            appBundleID: bundleID,
            textBeforeCursor: prefix,
            wordBeingTyped: lastWord,
            cursorIndex: cursorIdx,
            fullText: text
        )
    }

    static func lastWord(in text: String) -> String {
        var result = ""
        for ch in text.reversed() {
            if ch.isLetter || ch.isNumber || ch == "'" {
                result.append(ch)
            } else {
                break
            }
        }
        return String(result.reversed())
    }

    /// Screen-coordinate rect of the caret (or selection) inside the focused
    /// text field, converted from AX top-left origin to AppKit bottom-left.
    /// Returns nil if the focused element doesn't expose caret bounds — fall
    /// back to `focusedFrame()` in that case.
    func caretFrame() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let elementUnwrapped = focused
        else { return nil }
        let element = elementUnwrapped as! AXUIElement

        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef
        else { return nil }
        let axRange = rangeValue as! AXValue

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axRange, .cfRange, &range) else { return nil }

        // The element's own AX frame (top-left origin) — we validate the
        // caret rect against it so we never anchor on the wrong line or a
        // bogus (0,0) rect.
        let elementRect = rawElementRect(element)

        // Probe order, taking the first plausible rect:
        //   1. exact caret (length 0) — most apps return a zero-width vertical
        //      rect right at the cursor; the most accurate anchor.
        //   2. the character BEFORE the cursor (length 1) — the just-typed glyph.
        //   3. the character AFTER the cursor (length 1).
        let candidates: [CFRange] = [
            CFRange(location: range.location, length: 0),
            range.location > 0 ? CFRange(location: range.location - 1, length: 1) : nil,
            CFRange(location: range.location, length: 1),
        ].compactMap { $0 }

        var rect: CGRect?
        for probe in candidates {
            guard let r = boundsForRange(probe, in: element) else { continue }
            if isPlausibleCaretRect(r, within: elementRect) {
                rect = r
                break
            }
        }
        guard let caret = rect else { return nil }

        // AX returns top-left origin coordinates relative to the primary
        // screen's frame. Convert to AppKit bottom-left.
        guard let screen = NSScreen.screens.first(where: {
                NSPointInRect(NSPoint(x: caret.origin.x, y: caret.origin.y), $0.frame)
              }) ?? NSScreen.main
        else { return caret }
        let flippedY = screen.frame.maxY - caret.origin.y - caret.height
        return CGRect(x: caret.origin.x, y: flippedY, width: caret.width, height: caret.height)
    }

    /// A caret rect is trustworthy only if it has real height, isn't pinned to
    /// the screen origin (some apps return (0,0,0,0) when they can't resolve a
    /// range), and — when we know the element's frame — actually sits inside
    /// that element. The last check is what stops us anchoring on line 1 when
    /// the cursor is really on line 3 of a multi-line field.
    private func isPlausibleCaretRect(_ rect: CGRect, within element: CGRect?) -> Bool {
        guard rect.height >= 1, rect.height < 200 else { return false }
        if rect.origin.x == 0, rect.origin.y == 0 { return false }
        if let element, element.width > 0, element.height > 0 {
            // Allow a little slack for descenders / sub-pixel rounding.
            let slack: CGFloat = 4
            let expanded = element.insetBy(dx: -slack, dy: -slack)
            // The caret's vertical midpoint must fall within the element.
            let mid = CGPoint(x: rect.midX, y: rect.midY)
            if !expanded.contains(mid) { return false }
        }
        return true
    }

    /// Raw AX frame of an element (top-left origin), or nil.
    private func rawElementRect(_ element: AXUIElement) -> CGRect? {
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, let sizeValue = sizeRef
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        let axPos = posValue as! AXValue
        let axSize = sizeValue as! AXValue
        guard AXValueGetValue(axPos, .cgPoint, &origin),
              AXValueGetValue(axSize, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The visual style of the text at the caret — host font + color — so the
    /// ghost overlay can render in the SAME typeface/size/color and read as
    /// inline text rather than a pasted-on overlay. Falls back to sensible
    /// defaults when the app doesn't expose attributed text.
    struct CaretStyle: Sendable, Equatable {
        var fontName: String?   // PostScript name, e.g. "Helvetica"
        var pointSize: CGFloat  // resolved point size
        var rgba: [CGFloat]?    // host text color components (sRGB), if known
    }

    func caretStyle() -> CaretStyle {
        let fallback = CaretStyle(fontName: nil, pointSize: 14, rgba: nil)
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let elementUnwrapped = focused
        else { return fallback }
        let element = elementUnwrapped as! AXUIElement

        // Resolve a 1-char range around the cursor to query its run attributes.
        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef
        else { return fallback }
        var sel = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &sel) else { return fallback }

        let loc = max(0, sel.location - 1)
        var probe = CFRange(location: loc, length: 1)
        guard let probeVal = AXValueCreate(.cfRange, &probe) else { return fallback }

        var attrRef: AnyObject?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXAttributedStringForRange" as CFString,
            probeVal,
            &attrRef
        )
        guard err == .success, let attr = attrRef as? NSAttributedString, attr.length > 0 else {
            return fallback
        }

        var style = fallback
        let attrs = attr.attributes(at: 0, effectiveRange: nil)
        if let font = attrs[.font] as? NSFont {
            style.fontName = font.fontName
            style.pointSize = font.pointSize
        }
        if let color = attrs[.foregroundColor] as? NSColor,
           let srgb = color.usingColorSpace(.sRGB) {
            style.rgba = [srgb.redComponent, srgb.greenComponent,
                          srgb.blueComponent, srgb.alphaComponent]
        }
        return style
    }

    /// Asks AX for the bounding rect of a text range. Returns the raw rect in
    /// AX coords (top-left origin) — caller is responsible for flipping.
    private func boundsForRange(_ range: CFRange, in element: AXUIElement) -> CGRect? {
        var mutable = range
        guard let value = AXValueCreate(.cfRange, &mutable) else { return nil }
        var boundsRef: AnyObject?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            value,
            &boundsRef
        )
        guard err == .success, let boundsValue = boundsRef else { return nil }
        let axBounds = boundsValue as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(axBounds, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Frame of the focused element, in screen coordinates (top-left origin
    /// converted to AppKit bottom-left).
    func focusedFrame() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let elementUnwrapped = focused
        else { return nil }
        let element = elementUnwrapped as! AXUIElement

        var posRef: AnyObject?
        var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, let sizeValue = sizeRef
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        let axPos = posValue as! AXValue
        let axSize = sizeValue as! AXValue
        guard AXValueGetValue(axPos, .cgPoint, &origin),
              AXValueGetValue(axSize, .cgSize, &size)
        else { return nil }

        // AX uses top-left origin on the main screen. Convert to AppKit bottom-left.
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(NSPoint(x: origin.x, y: origin.y), $0.frame) }) ?? NSScreen.main else {
            return CGRect(origin: origin, size: size)
        }
        let flippedY = screen.frame.maxY - origin.y - size.height
        return CGRect(x: origin.x, y: flippedY, width: size.width, height: size.height)
    }
}
