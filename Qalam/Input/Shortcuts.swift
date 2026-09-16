import Foundation
import CoreGraphics

/// Virtual key codes QalamAI's shortcuts use. Key codes name PHYSICAL keys,
/// so every shortcut works the same on any keyboard layout (English, Arabic,
/// AZERTY…) — matching is always keycode + exact modifiers, never characters.
enum KeyCode {
    static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let rightArrow: Int64 = 124
    static let space: Int64 = 49
    /// kVK_ANSI_Grave: the key above Tab on ANSI keyboards (types ذ on the
    /// Arabic layout). On ISO keyboards it's the key beside left Shift.
    static let grave: Int64 = 50
    /// kVK_ISO_Section: the key above Tab on ISO keyboards.
    static let isoSection: Int64 = 10
    static let rightBracket: Int64 = 30
    static let r: Int64 = 15
    static let backslash: Int64 = 42
    /// Number row 1–5 and keypad 1–5 → option index (T7 alternatives list).
    static let digits: [Int64: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
                                       83: 1, 84: 2, 85: 3, 86: 4, 87: 5]

    /// "The key above Tab" — both codes are accepted by design, so the
    /// shortcut works on ANSI and ISO boards alike.
    static func isAboveTab(_ keyCode: Int64) -> Bool {
        keyCode == grave || keyCode == isoSection
    }
}

/// The four modifiers that make a shortcut. Built from `CGEventFlags`
/// ignoring Fn, NumPad, Caps Lock and Help — arrow keys always carry Fn +
/// NumPad, and Caps Lock must never change what a shortcut means.
struct KeyMods: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let command = KeyMods(rawValue: 1 << 0)
    static let control = KeyMods(rawValue: 1 << 1)
    static let option  = KeyMods(rawValue: 1 << 2)
    static let shift   = KeyMods(rawValue: 1 << 3)

    init(rawValue: UInt8) { self.rawValue = rawValue }

    init(_ flags: CGEventFlags) {
        var mods: KeyMods = []
        if flags.contains(.maskCommand)   { mods.insert(.command) }
        if flags.contains(.maskControl)   { mods.insert(.control) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskShift)     { mods.insert(.shift) }
        self = mods
    }

    /// No ⌘, ⌃ or ⌥ held (⇧ may be).
    var hasNoCommandControlOption: Bool {
        isDisjoint(with: [.command, .control, .option])
    }
}

// MARK: - Catalog (Settings → Shortcuts)

/// Which card a shortcut is listed in.
enum ShortcutSection: Sendable {
    /// Keys that act on a visible suggestion (they pass through otherwise).
    case suggestion
    /// Global shortcuts.
    case anywhere
}

/// One row of the Shortcuts tab. `keys` are display labels (layout-
/// independent: they name the physical keys). A row with `isEnabled` /
/// `setEnabled` shows an on/off switch.
struct ShortcutInfo: Identifiable {
    let id: String
    let section: ShortcutSection
    let keys: [String]
    let title: LocalizationKey
    let help: LocalizationKey
    /// Extra caption lines shown under `help`.
    var notes: [LocalizationKey] = []
    var isEnabled: (@MainActor () -> Bool)? = nil
    var setEnabled: (@MainActor (Bool) -> Void)? = nil
}

/// Every shortcut QalamAI handles, in display order. Later tasks append rows.
@MainActor
enum ShortcutCatalog {
    static var all: [ShortcutInfo] {
        let prefs = UserPreferences.shared
        let tabAccepts = prefs.acceptWordKey != "rightArrow"
        let acceptKey = tabAccepts ? "⇥" : "→"
        let aboveTab = L.t(.shortcutKeyAboveTab)

        var rows: [ShortcutInfo] = [
            ShortcutInfo(id: "acceptWord", section: .suggestion, keys: [acceptKey],
                         title: .shortcutAcceptWord, help: .shortcutAcceptWordHelp,
                         notes: tabAccepts ? [.shortcutTabPassNote] : []),
            ShortcutInfo(id: "acceptAll", section: .suggestion, keys: ["⇧", acceptKey],
                         title: .shortcutAcceptAll, help: .shortcutAcceptAllHelp),
        ]
        if tabAccepts {
            rows.append(ShortcutInfo(id: "realTab", section: .suggestion, keys: ["⌥", "⇥"],
                                     title: .shortcutRealTab, help: .shortcutRealTabHelp))
        }
        rows += [
            ShortcutInfo(id: "acceptAllAboveTab", section: .suggestion, keys: [aboveTab],
                         title: .shortcutAcceptAllAboveTab, help: .shortcutAcceptAllAboveTabHelp,
                         isEnabled: { UserPreferences.shared.acceptAllKeyAboveTab },
                         setEnabled: { UserPreferences.shared.acceptAllKeyAboveTab = $0 }),
            ShortcutInfo(id: "dismiss", section: .suggestion, keys: ["Esc"],
                         title: .shortcutDismiss, help: .shortcutDismissHelp),
            ShortcutInfo(id: "regenerate", section: .suggestion, keys: ["⌥", "]"],
                         title: .shortcutRegenerate, help: .shortcutRegenerateHelp),
            ShortcutInfo(id: "alternatives", section: .suggestion, keys: ["⌥", "\\"],
                         title: .shortcutAlternatives, help: .shortcutAlternativesHelp,
                         isEnabled: { UserPreferences.shared.shortcutAlternativesEnabled },
                         setEnabled: { UserPreferences.shared.shortcutAlternativesEnabled = $0 }),
            ShortcutInfo(id: "insertAlternative", section: .suggestion, keys: ["1", "…", "5"],
                         title: .shortcutInsertAlternative, help: .shortcutInsertAlternativeHelp),

            ShortcutInfo(id: "pause", section: .anywhere, keys: ["⌘", "⇧", "Space"],
                         title: .shortcutPauseResume, help: .shortcutPauseHelp,
                         notes: [.shortcutEditorsPassHelp],
                         isEnabled: { UserPreferences.shared.shortcutPauseEnabled },
                         setEnabled: { UserPreferences.shared.shortcutPauseEnabled = $0 }),
            ShortcutInfo(id: "forceActivate", section: .anywhere, keys: ["⌃", aboveTab],
                         title: .shortcutForceActivate, help: .shortcutForceActivateHelp,
                         notes: [.shortcutForceEditorsHelp],
                         isEnabled: { UserPreferences.shared.shortcutForceActivateEnabled },
                         setEnabled: { UserPreferences.shared.shortcutForceActivateEnabled = $0 }),
            ShortcutInfo(id: "appToggle", section: .anywhere, keys: ["⌃", "⌥", "⌘", aboveTab],
                         title: .shortcutAppToggle, help: .shortcutAppToggleHelp,
                         isEnabled: { UserPreferences.shared.shortcutAppToggleEnabled },
                         setEnabled: { UserPreferences.shared.shortcutAppToggleEnabled = $0 }),
            ShortcutInfo(id: "rewrite", section: .anywhere, keys: ["⌃", "⌥", "R"],
                         title: .shortcutRewrite, help: .shortcutRewriteHelp),
        ]
        return rows
    }
}
