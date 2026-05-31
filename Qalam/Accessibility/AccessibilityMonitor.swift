import Foundation
import AppKit
import ApplicationServices

struct TextContext: Sendable, Equatable {
    let appBundleID: String?
    let appName: String?          // localized frontmost-app name, e.g. "Mail"
    let textBeforeCursor: String
    let textAfterCursor: String   // suffix in the same field, bounded
    let wordBeingTyped: String
    let cursorIndex: Int
    let fullText: String

    static let empty = TextContext(appBundleID: nil, appName: nil, textBeforeCursor: "", textAfterCursor: "", wordBeingTyped: "", cursorIndex: 0, fullText: "")
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

        // Suffix (text after the cursor) — bounded. Lets the model write a
        // continuation that fits what already follows the caret.
        var suffix = String(text[index...])
        if suffix.count > 240 { suffix = String(suffix.prefix(240)) }

        let lastWord = AccessibilityMonitor.lastWord(in: prefix)
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        let appName = frontApp?.localizedName

        return TextContext(
            appBundleID: bundleID,
            appName: appName,
            textBeforeCursor: prefix,
            textAfterCursor: suffix,
            wordBeingTyped: lastWord,
            cursorIndex: cursorIdx,
            fullText: text
        )
    }

    /// Broader surrounding context: visible static-text near the focused field
    /// (e.g. the message thread above a reply box). Walks up to the focused
    /// element's parent and collects sibling/descendant `AXValue`/`AXTitle`
    /// static text. Bounded and best-effort — returns "" if nothing useful.
    private var cachedSurrounding: (text: String, at: Date)?

    func surroundingText(maxChars: Int = 600) -> String {
        // Cache the result: the recursive AX tree walk below is expensive in
        // heavy WebKit editors (Apple Notes), and running it on every debounced
        // keystroke was the main source of per-keystroke lag. Surrounding
        // context changes slowly, so refreshing at most every ~1.5s is plenty.
        if let cached = cachedSurrounding, Date().timeIntervalSince(cached.at) < 1.5 {
            return cached.text
        }
        let result = computeSurroundingText(maxChars: maxChars)
        cachedSurrounding = (result, Date())
        return result
    }

    private func computeSurroundingText(maxChars: Int = 600) -> String {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let unwrapped = focused
        else { return "" }
        let element = unwrapped as! AXUIElement

        var parentRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
              let parentUnwrapped = parentRef
        else { return "" }
        let parent = parentUnwrapped as! AXUIElement

        var collected: [String] = []
        collectStaticText(from: parent, into: &collected, budget: maxChars, depth: 0)
        let joined = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(joined.prefix(maxChars))
    }

    private func collectStaticText(from element: AXUIElement,
                                   into out: inout [String],
                                   budget: Int,
                                   depth: Int) {
        // Bound the walk so we never stall on huge AX trees.
        if depth > 4 { return }
        if out.reduce(0, { $0 + $1.count }) > budget { return }

        var roleRef: AnyObject?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String) : nil

        if role == "AXStaticText" {
            var valueRef: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let s = valueRef as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count >= 2 { out.append(t) }
            }
        }

        var childrenRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children.prefix(40) {
                collectStaticText(from: child, into: &out, budget: budget, depth: depth + 1)
                if out.reduce(0, { $0 + $1.count }) > budget { break }
            }
        }
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

        // The element's own AX frame (top-left origin) — we validate the
        // caret rect against it so we never anchor on the wrong line or a
        // bogus (0,0) rect.
        let elementRect = rawElementRect(element)

        var rect: CGRect?

        // PRIMARY for WebKit-based editors (Apple Notes, Mail compose, web text
        // fields): the TextMarker API. These apps implement the AXTextMarker
        // attributes accurately but return STALE/wrong rects from the CFRange
        // `AXBoundsForRange` path — which is why the ghost landed on the wrong
        // line in Notes. Try markers first; fall back to CFRange for apps like
        // TextEdit that don't expose markers.
        if let r = caretRectViaTextMarker(element),
           isPlausibleCaretRect(r, within: elementRect) {
            rect = r
        }

        if rect == nil {
            var rangeRef: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
               let rangeValue = rangeRef {
                let axRange = rangeValue as! AXValue
                var range = CFRange(location: 0, length: 0)
                if AXValueGetValue(axRange, .cfRange, &range) {
                    // CRITICAL: in NSTextView-backed AXTextAreas (Apple Notes,
                    // Dia, many native editors) the ZERO-LENGTH caret bounds
                    // report a broken Y (stuck on the wrong line), but a
                    // NON-ZERO 1-char range reports the correct line.
                    //
                    // So combine the two: take the horizontal position (X) from
                    // the ZERO-LENGTH caret (it tracks the cursor accurately,
                    // LTR and RTL alike — only its Y is wrong), and take the
                    // line Y + height from a 1-char range. This is exact and
                    // direction-agnostic, so it fixes both the LTR overlap and
                    // the RTL "far away" placement without guessing edges.
                    let zeroCaret = boundsForRange(CFRange(location: range.location, length: 0), in: element)
                    let beforeChar = range.location > 0
                        ? boundsForRange(CFRange(location: range.location - 1, length: 1), in: element) : nil
                    let afterChar = boundsForRange(CFRange(location: range.location, length: 1), in: element)
                    let lineRect = [beforeChar, afterChar]
                        .compactMap { $0 }
                        .first { isPlausibleCaretRect($0, within: elementRect) }

                    // The zero-length caret's X is only trustworthy if it falls
                    // inside the field. Some apps (Terminal, Chromium) return a
                    // garbage caret rect like (0,1080,0,0) — using its x=0 threw
                    // the ghost to the far-left of the screen. Validate it; if
                    // it's bogus, use the trailing edge of the char before the
                    // cursor (a real rendered glyph = the true cursor X).
                    let zeroXUsable: Bool = {
                        guard let z = zeroCaret, z.minX.isFinite, z.minY.isFinite else { return false }
                        if let e = elementRect, e.width > 0 {
                            return z.minX >= e.minX - 4 && z.minX <= e.maxX + 4
                        }
                        return z.minX != 0 || z.minY != 0
                    }()

                    if zeroXUsable, let z = zeroCaret, let ls = lineRect {
                        // True cursor X (validated) + correct line Y.
                        rect = CGRect(x: z.minX, y: ls.minY, width: 0, height: ls.height)
                    } else if let ls = lineRect {
                        // Garbage/no caret X — the char-before's trailing edge IS
                        // the cursor. (Correct line Y comes with it.)
                        rect = CGRect(x: ls.maxX, y: ls.minY, width: 0, height: ls.height)
                    } else if let z = zeroCaret, isPlausibleCaretRect(z, within: elementRect) {
                        rect = z
                    }
                }
            }
        }

        guard let caret = rect else { return nil }

        // AX/Quartz global coordinates use a TOP-LEFT origin (y grows down from
        // the top of the PRIMARY display). AppKit uses a BOTTOM-LEFT origin (y
        // grows up). The conversion is a single global transform based on the
        // primary display's height — it does NOT depend on which monitor the
        // caret is on. The previous code matched a top-left point against
        // bottom-left screen frames, which on multi-monitor setups selected the
        // wrong screen and offset the ghost vertically ("above the line"). Use
        // the primary screen height for a correct global flip.
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero }
                             ?? NSScreen.main)?.frame.height ?? caret.maxY
        let flippedY = primaryHeight - caret.origin.y - caret.height
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
        var style = CaretStyle(fontName: nil, pointSize: 14, rgba: nil)
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let elementUnwrapped = focused
        else { return style }
        let element = elementUnwrapped as! AXUIElement

        // 1) Best source: the attributed run at the cursor. Try a couple of
        //    nearby ranges since some apps return empty attrs at the very tail.
        if let sel = selectedCFRange(of: element) {
            let probes = [
                CFRange(location: max(0, sel.location - 1), length: 1),
                CFRange(location: sel.location, length: 1),
                CFRange(location: max(0, sel.location - 2), length: 1),
            ]
            for probe in probes {
                if applyAttributedStyle(into: &style, element: element, range: probe) { break }
            }
        }

        // 2) Fallback: element-level font / color attributes (some Cocoa text
        //    views expose these directly even when the attributed-string call
        //    returns nothing).
        if style.fontName == nil {
            var fontRef: AnyObject?
            if AXUIElementCopyAttributeValue(element, "AXFont" as CFString, &fontRef) == .success {
                if let font = fontRef as? NSFont {
                    style.fontName = font.fontName; style.pointSize = font.pointSize
                } else if let dict = fontRef as? [String: Any] {
                    // AXFont can come back as a dict {AXFontName, AXFontSize}.
                    if let name = dict["AXFontName"] as? String { style.fontName = name }
                    if let size = dict["AXFontSize"] as? CGFloat { style.pointSize = size }
                    else if let size = (dict["AXFontSize"] as? NSNumber)?.doubleValue { style.pointSize = CGFloat(size) }
                }
            }
        }
        if style.rgba == nil {
            var colorRef: AnyObject?
            if AXUIElementCopyAttributeValue(element, "AXForegroundColor" as CFString, &colorRef) == .success,
               CFGetTypeID(colorRef as CFTypeRef) == CGColor.typeID {
                let cg = colorRef as! CGColor
                if let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
                    style.rgba = [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent]
                }
            }
        }
        return style
    }

    private func selectedCFRange(of element: AXUIElement) -> CFRange? {
        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else { return nil }
        var sel = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &sel) else { return nil }
        return sel
    }

    /// Reads font + foreground color from the attributed run for `range`.
    /// Returns true if it found at least a font.
    private func applyAttributedStyle(into style: inout CaretStyle,
                                      element: AXUIElement, range: CFRange) -> Bool {
        var probe = range
        guard let probeVal = AXValueCreate(.cfRange, &probe) else { return false }
        var attrRef: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, "AXAttributedStringForRange" as CFString, probeVal, &attrRef) == .success,
              let attr = attrRef as? NSAttributedString, attr.length > 0
        else { return false }

        let attrs = attr.attributes(at: 0, effectiveRange: nil)
        var foundFont = false
        if let font = attrs[.font] as? NSFont {
            style.fontName = font.fontName
            style.pointSize = font.pointSize
            foundFont = true
        }
        if let color = attrs[.foregroundColor] as? NSColor,
           let srgb = color.usingColorSpace(.sRGB) {
            style.rgba = [srgb.redComponent, srgb.greenComponent,
                          srgb.blueComponent, srgb.alphaComponent]
        }
        return foundFont
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

    /// Caret rect via the AXTextMarker API (top-left origin), used by WebKit
    /// editors (Apple Notes, Mail, web inputs). They expose
    /// `AXSelectedTextMarkerRange` + `AXBoundsForTextMarkerRange` accurately,
    /// while their CFRange `AXBoundsForRange` is stale/wrong (wrong line).
    /// Returns nil for apps that don't implement text markers (e.g. TextEdit),
    /// so the caller falls back to the CFRange path.
    private func caretRectViaTextMarker(_ element: AXUIElement) -> CGRect? {
        var markerRangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
                element,
                "AXSelectedTextMarkerRange" as CFString,
                &markerRangeRef) == .success,
              let markerRange = markerRangeRef
        else { return nil }

        var boundsRef: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
                element,
                "AXBoundsForTextMarkerRange" as CFString,
                markerRange as CFTypeRef,
                &boundsRef) == .success,
              let boundsValue = boundsRef,
              CFGetTypeID(boundsValue as CFTypeRef) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
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

        guard size.width > 0, size.height > 0 else { return nil }
        // Same global top-left→bottom-left flip as caretFrame() (primary-screen
        // height), so the field frame and the caret share one coordinate space.
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero }
                             ?? NSScreen.main)?.frame.height ?? (origin.y + size.height)
        let flippedY = primaryHeight - origin.y - size.height
        return CGRect(x: origin.x, y: flippedY, width: size.width, height: size.height)
    }
}
