import Foundation

// String-backed enums for `UserPreferences` values. Each is stored as its
// `rawValue` and read back with `Enum(rawValue:) ?? default`, so an unknown
// value written by a newer version falls back to the default instead of
// failing.
//
// Per-app / per-site enums (`ProfileActivation`, `DisplayMode`,
// `LanguagePreference`) live with `AppProfile` in AppProfile.swift.

/// What to show when the caret's position can't be read (T5). Stored in
/// `UserPreferences.caretUnavailableBehavior`; default `.bubble`.
enum CaretUnavailableBehavior: String, CaseIterable, Sendable {
    /// Show the suggestion in a small bubble anchored to the text field.
    case bubble
    /// Show nothing (pre-1.4 behaviour); the accept keys reach the app.
    case hide
}

/// What Esc does while a suggestion is visible (T4). Stored in
/// `UserPreferences.escBehavior`; default `.dismissOnly` (= Esc before 1.4).
enum EscBehavior: String, CaseIterable, Sendable {
    /// Hide the suggestion; Esc does not reach the app.
    case dismissOnly
    /// Hide it and keep this field quiet for 15 seconds (or until focus
    /// moves to another field, or the user forces a suggestion).
    case dismissAndPause
    /// Hide it and let the app receive Esc too (close a dialog, leave a mode).
    case passThrough
}

/// What counts as writing worth learning from (T6). Stored in
/// `UserPreferences.recordWritingMode`; default `.acceptedOnly`.
enum RecordWritingMode: String, CaseIterable, Sendable {
    /// Only stretches of text where the user accepted a suggestion.
    case acceptedOnly
    /// Everything typed in fields QalamAI is allowed to work in.
    case everything
}

/// How much of the user's own writing is fed back into the prompt (T6).
/// Stored in `UserPreferences.personalizationStrength`; default `.off`
/// (set to `.medium` the first time recording is switched on).
enum PersonalizationStrength: String, CaseIterable, Sendable {
    case off, low, medium, strong
}

/// How a spelling / grammar fix is drawn (T7). Stored in
/// `UserPreferences.autocorrectStyle`; default `.inline` (= pre-1.4).
///
/// Neither style ever changes the user's text on its own — the fix is shown
/// and applied only when the accept key is pressed.
enum AutocorrectStyle: String, CaseIterable, Sendable {
    /// The corrected word alone, drawn like any other suggestion.
    case inline
    /// "recieve → receive": the typo and the fix, so the change is obvious.
    case arrow
}

/// Preset suggestion lengths (T7). This is a VIEW of the existing
/// `maxSuggestionWords` preference — there is no separate stored value — so
/// the slider and the chips can never disagree.
enum CompletionLength: String, CaseIterable, Sendable {
    case short, medium, long

    /// Which preset a stored word budget corresponds to on this model.
    /// `.medium` is what every install had before 1.4 (5 words).
    static func from(words: Int, modelMax: Int) -> CompletionLength {
        if words <= 3 { return .short }
        if modelMax > 5, words >= modelMax { return .long }
        return .medium
    }

    /// The word budget this preset asks for, clamped to the model's ceiling.
    func words(modelMax: Int) -> Int {
        let cap = max(1, modelMax)
        switch self {
        case .short:  return min(3, cap)
        case .medium: return min(5, cap)
        case .long:   return cap
        }
    }

    /// Short suggestions stop at the end of the first clause, so they read as
    /// a finished thought instead of a cut-off sentence.
    var stopsAtClause: Bool { self == .short }
}
