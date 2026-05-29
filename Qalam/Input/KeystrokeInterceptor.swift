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
    private var isPaused = false

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
            NSLog("QalamAI: failed to create CGEventTap — needs Accessibility permission")
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

    func pause()  { isPaused = true }
    func resume() { isPaused = false }

    // MARK: - C callback

    private static let tapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<KeystrokeInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
        return interceptor.handle(proxy: proxy, type: type, event: event)
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard !isPaused else { return Unmanaged.passUnretained(event) }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let shiftDown = flags.contains(.maskShift)

        // Cheap synchronous read of suggestion state.
        let hasSuggestion = MainActor.assumeIsolated {
            SuggestionEngine.shared.currentSuggestion != nil &&
            !(SuggestionEngine.shared.currentSuggestion?.isEmpty ?? true)
        }

        // Key codes: Tab = 48, Escape = 53, Right Arrow = 124.
        // The "accept next word" key is configurable (Tab or →). Whichever it
        // is, holding Shift accepts the whole suggestion.
        let acceptKeyCode: Int64 = MainActor.assumeIsolated {
            UserPreferences.shared.acceptWordKey == "rightArrow" ? 124 : 48
        }
        if keyCode == acceptKeyCode && hasSuggestion {
            // Right Arrow with no suggestion must still move the caret, so we
            // only consume it when a suggestion is showing (guarded above).
            MainActor.assumeIsolated {
                if shiftDown {
                    SuggestionEngine.shared.acceptAll()
                } else {
                    SuggestionEngine.shared.acceptNextWord()
                }
            }
            return nil   // consume
        }
        if keyCode == 53 && hasSuggestion {
            MainActor.assumeIsolated {
                SuggestionEngine.shared.dismiss()
            }
            return nil   // consume
        }
        // Option + ] (keyCode 30) cycles to an alternative completion.
        if keyCode == 30 && flags.contains(.maskAlternate) && hasSuggestion {
            MainActor.assumeIsolated {
                SuggestionEngine.shared.cycleAlternative()
            }
            return nil   // consume
        }
        // Control + Option + R (keyCode 15) → tone-rewrite the current selection.
        if keyCode == 15 && flags.contains(.maskControl) && flags.contains(.maskAlternate) {
            MainActor.assumeIsolated {
                SelectionRewriter.shared.begin()
            }
            return nil   // consume
        }

        // Pump AX state after this key lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
            AccessibilityMonitor.shared.pump()
        }
        return Unmanaged.passUnretained(event)
    }
}
