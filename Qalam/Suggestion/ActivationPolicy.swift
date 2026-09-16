import Foundation
import CoreGraphics

/// Why suggestions can't run at all — even the force-activate shortcut is
/// refused.
enum ActivationBlock: Sendable, Equatable {
    case secureInput, secureField, noField, globallyDisabled, snoozed, appOff, appTemporarilyPaused
}

/// Why no AUTOMATIC suggestion is offered. Force-activate overrides these.
enum ActivationIdle: Sendable, Equatable {
    case forceOnly, searchField, comboBox, addressBar, narrowField
}

enum ActivationDecision: Sendable, Equatable {
    case allow
    case idle(ActivationIdle)
    case blocked(ActivationBlock)
}

/// The single place that decides whether a field gets suggestions.
///
/// Order: hard blocks (Secure Input, no readable field, password field,
/// global pause, snooze, app/site Off, temporary app pause) → force-activate
/// → the profile's Force only / Always on → idle heuristics.
///
/// The heuristics apply only to `.automatic` profiles and only skip fields
/// where completion is noise: search fields, combo boxes, a browser's own
/// address bar, and narrow single-line text fields. Terminals, code editors
/// and every multi-line field (AXTextArea etc.) are never idled — apps are
/// idled only by an explicit per-app profile.
@MainActor
enum ActivationPolicy {
    /// Single-line fields narrower than this (points) get no automatic
    /// suggestions — there is no room to show one.
    static let narrowFieldWidth: CGFloat = 180

    static func evaluate(_ context: TextContext, profile: ResolvedProfile, forced: Bool) -> ActivationDecision {
        let prefs = UserPreferences.shared
        if SecureInputMonitor.shared.isActive { return .blocked(.secureInput) }
        // No focused text element could be read. An existing field whose
        // text is empty is NOT this (force-activate must work there).
        if context == .empty { return .blocked(.noField) }
        if context.role == "AXSecureTextField" || context.subrole == "AXSecureTextField" {
            return .blocked(.secureField)
        }
        if !prefs.isEnabled { return .blocked(.globallyDisabled) }
        if prefs.isSnoozed { return .blocked(.snoozed) }
        if profile.activation == .off { return .blocked(.appOff) }
        if profile.isTemporarilyPaused { return .blocked(.appTemporarilyPaused) }

        if forced { return .allow }
        switch profile.activation {
        case .forceOnly: return .idle(.forceOnly)
        case .alwaysOn:  return .allow
        case .automatic, .off: break
        }

        // Heuristics (automatic only).
        if context.subrole == "AXSearchField" { return .idle(.searchField) }
        if context.role == "AXComboBox" { return .idle(.comboBox) }
        // A browser's address / chrome field: only when the parent walk
        // positively reached the window without passing page content. Unknown
        // (nil) never idles, so a failed walk can't silence web forms. The
        // Firefox family has no reliable AXWebArea and is skipped.
        if let bundleID = context.appBundleID,
           KnownApps.webAreaReliableBrowsers.contains(bundleID),
           context.role == "AXTextField" || context.role == "AXComboBox",
           context.isInWebArea == false {
            return .idle(.addressBar)
        }
        // A zero width is a bogus AX size, not a narrow field.
        if context.role == "AXTextField", let size = context.fieldSize,
           size.width > 0, size.width < narrowFieldWidth {
            return .idle(.narrowField)
        }
        return .allow
    }

    /// May this field's text be kept as a writing sample (T6)?
    ///
    /// Stricter than `evaluate`: the idle rules don't apply (a search box the
    /// user wrote a paragraph in is still their writing), but every hard
    /// block does, plus the profile's own "Learn from my writing" switch —
    /// off by default in terminals.
    static func allowsRecording(_ context: TextContext, profile: ResolvedProfile) -> Bool {
        let prefs = UserPreferences.shared
        if SecureInputMonitor.shared.isActive { return false }
        if context == .empty { return false }
        if context.role == "AXSecureTextField" || context.subrole == "AXSecureTextField" {
            return false
        }
        if !prefs.isEnabled || prefs.isSnoozed { return false }
        if profile.activation == .off { return false }
        if profile.isTemporarilyPaused { return false }
        return profile.recordWriting
    }
}
