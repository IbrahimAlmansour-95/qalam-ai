import Foundation
import Observation

@MainActor
@Observable
final class UserPreferences {
    static let shared = UserPreferences()

    private let defaults: UserDefaults = QalamDefaults.suite

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }
    var activeModelTag: String {
        didSet {
            defaults.set(activeModelTag, forKey: Keys.activeModelTag)
            // Unload the previous model and pre-load the new one.
            if oldValue != activeModelTag {
                ModelManager.shared.activeModelDidChange(from: oldValue)
            }
        }
    }
    var suggestionDelayMs: Int {
        didSet { defaults.set(suggestionDelayMs, forKey: Keys.suggestionDelayMs) }
    }
    var triggerThreshold: Int {
        didSet { defaults.set(triggerThreshold, forKey: Keys.triggerThreshold) }
    }
    /// Legacy (≤1.3.x). Read once by ProfileStore migration. Exclusions now
    /// live in per-app profiles; this is never written again, so the key
    /// stays on disk untouched for a downgrade.
    private(set) var excludedBundleIDs: [String]
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) }
    }
    var activeModeID: String {
        didSet { defaults.set(activeModeID, forKey: Keys.activeModeID) }
    }
    var autoCorrectEnabled: Bool {
        didSet { defaults.set(autoCorrectEnabled, forKey: Keys.autoCorrectEnabled) }
    }
    var autoGrammarEnabled: Bool {
        didSet { defaults.set(autoGrammarEnabled, forKey: Keys.autoGrammarEnabled) }
    }
    /// How many words a single suggestion may produce. UI clamps this between
    /// 1 and the active model's `speed.maxSuggestionWords`.
    var maxSuggestionWords: Int {
        didSet { defaults.set(maxSuggestionWords, forKey: Keys.maxSuggestionWords) }
    }
    /// First-launch timestamp — kept for usage stats only, no trial logic.
    var firstLaunchDate: Date {
        didSet { defaults.set(firstLaunchDate.timeIntervalSince1970, forKey: Keys.firstLaunchDate) }
    }

    // MARK: - Context sources (all opt-in, privacy-sensitive)

    /// Inject recent clipboard text into the prompt as extra context.
    var clipboardContextEnabled: Bool {
        didSet { defaults.set(clipboardContextEnabled, forKey: Keys.clipboardContextEnabled) }
    }
    /// Read the whole focused field + nearby on-screen text via Accessibility
    /// (e.g. the email thread above a reply box) and feed it as surrounding
    /// context. Permission-free; on by default since it just uses AX we
    /// already have.
    var broaderContextEnabled: Bool {
        didSet { defaults.set(broaderContextEnabled, forKey: Keys.broaderContextEnabled) }
    }
    /// Capture a screenshot around the caret and OCR it for visual context.
    /// Requires Screen Recording permission; off by default.
    var screenContextEnabled: Bool {
        didSet { defaults.set(screenContextEnabled, forKey: Keys.screenContextEnabled) }
    }

    // MARK: - Inference engine

    /// "ollama" (bundled local models) or "appleIntelligence" (on-device
    /// Foundation Model, macOS 26+).
    var engine: String {
        didSet { defaults.set(engine, forKey: Keys.engine) }
    }

    /// Insert a trailing space after accepting a word with Tab.
    var spaceAfterAccept: Bool {
        didSet { defaults.set(spaceAfterAccept, forKey: Keys.spaceAfterAccept) }
    }

    /// Check GitHub for a newer release on launch + periodically.
    var autoUpdateEnabled: Bool {
        didSet { defaults.set(autoUpdateEnabled, forKey: Keys.autoUpdateEnabled) }
    }

    /// Which key accepts the next word: "tab" or "rightArrow".
    var acceptWordKey: String {
        didSet { defaults.set(acceptWordKey, forKey: Keys.acceptWordKey) }
    }

    /// Show a faint ⇥ hint at the end of the ghost text.
    var showAcceptHint: Bool {
        didSet { defaults.set(showAcceptHint, forKey: Keys.showAcceptHint) }
    }

    /// Suggestions are paused until this date (snooze). nil/past = active.
    var snoozeUntil: Date? {
        didSet {
            if let d = snoozeUntil { defaults.set(d.timeIntervalSince1970, forKey: Keys.snoozeUntil) }
            else { defaults.removeObject(forKey: Keys.snoozeUntil) }
        }
    }
    var isSnoozed: Bool {
        if let until = snoozeUntil { return Date() < until }
        return false
    }

    /// User-added Ollama tags beyond the curated registry.
    var customModelTags: [String] {
        didSet { defaults.set(customModelTags, forKey: Keys.customModelTags) }
    }

    /// UI theme: "system" (follow macOS), "light", or "dark".
    var appearance: String {
        didSet {
            defaults.set(appearance, forKey: Keys.appearance)
            AppearanceManager.apply(appearance)
        }
    }

    /// Inline ghost-text calibration for apps that misreport caret geometry
    /// (e.g. Apple Notes). `ghostSizeScale` multiplies the ghost font size;
    /// `ghostVerticalOffset` nudges it in points (positive = down). Defaults
    /// (1.0, 0) are no-ops for well-behaved apps.
    var ghostSizeScale: Double {
        didSet { defaults.set(ghostSizeScale, forKey: Keys.ghostSizeScale) }
    }
    var ghostVerticalOffset: Double {
        didSet { defaults.set(ghostVerticalOffset, forKey: Keys.ghostVerticalOffset) }
    }

    /// Free text about the user / how they write, added to every suggestion
    /// request (per-app and per-site instructions are appended). The UI caps
    /// it at `ProfileStore.globalInstructionsLimit` characters.
    var customInstructions: String {
        didSet {
            defaults.set(customInstructions, forKey: Keys.customInstructions)
            // Empty instructions are not synced at all, so clearing them
            // reads as a deletion on the other Mac (and a Mac that never
            // wrote any can't wipe one that did).
            if customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SyncHooks.deleted(SyncKey.customInstructions)
            } else {
                SyncHooks.changed(SyncKey.customInstructions)
            }
        }
    }

    // MARK: - Sync (iCloud Drive, off by default)

    /// Keep snippets, modes, app/site settings, custom instructions and My
    /// Info in step with the user's other Macs through an encrypted file in
    /// iCloud Drive. Nothing is touched under Mobile Documents while this is
    /// off.
    var syncEnabled: Bool {
        didSet { defaults.set(syncEnabled, forKey: Keys.syncEnabled) }
    }

    /// Also sync the encrypted writing samples (a second, separate opt-in —
    /// these are the most personal thing QalamAI stores).
    var syncIncludePersonalization: Bool {
        didSet { defaults.set(syncIncludePersonalization, forKey: Keys.syncIncludePersonalization) }
    }

    // MARK: - Display

    /// What to show when the caret position can't be read (Electron canvas
    /// editors and the like): a bubble anchored to the field, or nothing.
    var caretUnavailableBehavior: CaretUnavailableBehavior {
        didSet {
            defaults.set(caretUnavailableBehavior.rawValue, forKey: Keys.caretUnavailableBehavior)
            OverlayCoordinator.shared.invalidate()
        }
    }

    /// Small QalamAI badge next to the focused text field (off by default).
    var showFieldButton: Bool {
        didSet {
            defaults.set(showFieldButton, forKey: Keys.showFieldButton)
            if !showFieldButton { FieldButtonPanel.shared.hide() }
        }
    }

    // MARK: - Shortcuts

    /// What Esc does while a suggestion is visible. Default: dismiss only.
    var escBehavior: EscBehavior {
        didSet { defaults.set(escBehavior.rawValue, forKey: Keys.escBehavior) }
    }
    /// ⌘⇧Space pauses / resumes suggestions everywhere.
    var shortcutPauseEnabled: Bool {
        didSet { defaults.set(shortcutPauseEnabled, forKey: Keys.shortcutPauseEnabled) }
    }
    /// ⌃ + the key above Tab asks for a suggestion right away.
    var shortcutForceActivateEnabled: Bool {
        didSet { defaults.set(shortcutForceActivateEnabled, forKey: Keys.shortcutForceActivateEnabled) }
    }
    /// ⌃⌥⌘ + the key above Tab pauses the frontmost app for 10 minutes.
    var shortcutAppToggleEnabled: Bool {
        didSet { defaults.set(shortcutAppToggleEnabled, forKey: Keys.shortcutAppToggleEnabled) }
    }
    /// While a suggestion is visible, the key above Tab accepts all of it.
    /// OFF by default: on the Arabic layout that key types ذ, and swallowing
    /// it unasked would stop the user typing that letter.
    var acceptAllKeyAboveTab: Bool {
        didSet { defaults.set(acceptAllKeyAboveTab, forKey: Keys.acceptAllKeyAboveTab) }
    }
    /// ⌥\ shows a short list of other words that could come next.
    var shortcutAlternativesEnabled: Bool {
        didSet { defaults.set(shortcutAlternativesEnabled, forKey: Keys.shortcutAlternativesEnabled) }
    }

    // MARK: - Suggestion behaviour

    /// Suggest while there is still text after the cursor on the same line.
    /// On by default — that is what QalamAI has always done.
    var midLineCompletion: Bool {
        didSet { defaults.set(midLineCompletion, forKey: Keys.midLineCompletion) }
    }

    /// Open the alternatives list by itself after a short pause in typing.
    var alternativesAutoShow: Bool {
        didSet {
            defaults.set(alternativesAutoShow, forKey: Keys.alternativesAutoShow)
            if !alternativesAutoShow { AlternativesProvider.shared.close() }
        }
    }

    /// How a spelling / grammar fix is drawn. Neither style edits the text on
    /// its own — the accept key still applies the fix.
    var autocorrectStyle: AutocorrectStyle {
        didSet {
            defaults.set(autocorrectStyle.rawValue, forKey: Keys.autocorrectStyle)
            OverlayCoordinator.shared.invalidate()
        }
    }

    // MARK: - Personalization

    /// Keep an encrypted local copy of what the user writes, so completions
    /// can sound like them. Off by default.
    var recordWritingEnabled: Bool {
        didSet {
            defaults.set(recordWritingEnabled, forKey: Keys.recordWritingEnabled)
            WritingRecorder.shared.settingsChanged()
            if recordWritingEnabled {
                // First time on: start using what we learn, at a middle
                // setting. A user who turned it back off keeps their choice.
                if personalizationStrength == .off { personalizationStrength = .medium }
                Task.detached { await PersonalizationStore.shared.loadIfNeeded() }
            }
        }
    }

    /// Which writing is kept: only text where a suggestion was accepted, or
    /// everything typed in fields QalamAI works in.
    var recordWritingMode: RecordWritingMode {
        didSet {
            defaults.set(recordWritingMode.rawValue, forKey: Keys.recordWritingMode)
            WritingRecorder.shared.settingsChanged()
        }
    }

    /// How much of the user's own writing is fed back into the prompt.
    var personalizationStrength: PersonalizationStrength {
        didSet {
            defaults.set(personalizationStrength.rawValue, forKey: Keys.personalizationStrength)
            if personalizationStrength != .off {
                Task.detached { await PersonalizationStore.shared.loadIfNeeded() }
            }
        }
    }

    private init() {
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.activeModelTag: "gemma4:e2b",
            Keys.suggestionDelayMs: Constants.Suggestion.defaultDelayMs,
            Keys.triggerThreshold: Constants.Suggestion.defaultTriggerThreshold,
            Keys.excludedBundleIDs: [String](),
            Keys.hasCompletedOnboarding: false,
            Keys.launchAtLogin: false,
            Keys.showInMenuBar: true,
            Keys.activeModeID: WritingMode.neutral.id,
            Keys.autoCorrectEnabled: true,
            Keys.autoGrammarEnabled: false,
            Keys.maxSuggestionWords: 5,
            Keys.clipboardContextEnabled: false,
            Keys.broaderContextEnabled: true,
            Keys.screenContextEnabled: false,
            Keys.engine: "ollama",
            Keys.spaceAfterAccept: true,
            Keys.autoUpdateEnabled: true,
            Keys.acceptWordKey: "tab",
            Keys.showAcceptHint: true,
            Keys.customModelTags: [String](),
            Keys.appearance: "system",
            Keys.ghostSizeScale: 1.0,
            Keys.ghostVerticalOffset: 0.0,
            Keys.customInstructions: "",
            Keys.caretUnavailableBehavior: CaretUnavailableBehavior.bubble.rawValue,
            Keys.showFieldButton: false,
            Keys.escBehavior: EscBehavior.dismissOnly.rawValue,
            Keys.shortcutPauseEnabled: true,
            Keys.shortcutForceActivateEnabled: true,
            Keys.shortcutAppToggleEnabled: true,
            Keys.acceptAllKeyAboveTab: false,
            Keys.shortcutAlternativesEnabled: true,
            Keys.midLineCompletion: true,
            Keys.alternativesAutoShow: false,
            Keys.autocorrectStyle: AutocorrectStyle.inline.rawValue,
            Keys.recordWritingEnabled: false,
            Keys.recordWritingMode: RecordWritingMode.acceptedOnly.rawValue,
            Keys.personalizationStrength: PersonalizationStrength.off.rawValue,
            Keys.syncEnabled: false,
            Keys.syncIncludePersonalization: false,
            // DO NOT register firstLaunchDate as a fallback — register's
            // value shifts every launch (it's a fresh Date()), which masks
            // the on-disk read with a non-zero in-memory default and the
            // "write on first launch" branch below never runs.
        ])

        self.isEnabled              = defaults.bool(forKey: Keys.isEnabled)
        self.activeModelTag         = defaults.string(forKey: Keys.activeModelTag) ?? "gemma4:e2b"
        self.suggestionDelayMs      = defaults.integer(forKey: Keys.suggestionDelayMs)
        self.triggerThreshold       = defaults.integer(forKey: Keys.triggerThreshold)
        self.excludedBundleIDs      = (defaults.array(forKey: Keys.excludedBundleIDs) as? [String]) ?? []
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.launchAtLogin          = defaults.bool(forKey: Keys.launchAtLogin)
        self.showInMenuBar          = defaults.bool(forKey: Keys.showInMenuBar)
        self.activeModeID           = defaults.string(forKey: Keys.activeModeID) ?? WritingMode.neutral.id
        self.autoCorrectEnabled     = defaults.bool(forKey: Keys.autoCorrectEnabled)
        self.autoGrammarEnabled     = defaults.bool(forKey: Keys.autoGrammarEnabled)
        self.maxSuggestionWords     = max(1, defaults.integer(forKey: Keys.maxSuggestionWords))
        self.clipboardContextEnabled = defaults.bool(forKey: Keys.clipboardContextEnabled)
        self.broaderContextEnabled   = defaults.bool(forKey: Keys.broaderContextEnabled)
        self.screenContextEnabled    = defaults.bool(forKey: Keys.screenContextEnabled)
        self.engine                  = defaults.string(forKey: Keys.engine) ?? "ollama"
        self.spaceAfterAccept        = defaults.bool(forKey: Keys.spaceAfterAccept)
        self.autoUpdateEnabled       = defaults.bool(forKey: Keys.autoUpdateEnabled)
        self.acceptWordKey           = defaults.string(forKey: Keys.acceptWordKey) ?? "tab"
        self.showAcceptHint          = defaults.bool(forKey: Keys.showAcceptHint)
        self.customModelTags         = (defaults.array(forKey: Keys.customModelTags) as? [String]) ?? []
        self.appearance              = defaults.string(forKey: Keys.appearance) ?? "system"
        self.ghostSizeScale          = defaults.object(forKey: Keys.ghostSizeScale) as? Double ?? 1.0
        self.ghostVerticalOffset     = defaults.object(forKey: Keys.ghostVerticalOffset) as? Double ?? 0.0
        self.customInstructions      = defaults.string(forKey: Keys.customInstructions) ?? ""
        self.caretUnavailableBehavior = CaretUnavailableBehavior(
            rawValue: defaults.string(forKey: Keys.caretUnavailableBehavior) ?? "") ?? .bubble
        self.showFieldButton         = defaults.bool(forKey: Keys.showFieldButton)
        self.escBehavior             = EscBehavior(rawValue: defaults.string(forKey: Keys.escBehavior) ?? "") ?? .dismissOnly
        self.shortcutPauseEnabled    = defaults.bool(forKey: Keys.shortcutPauseEnabled)
        self.shortcutForceActivateEnabled = defaults.bool(forKey: Keys.shortcutForceActivateEnabled)
        self.shortcutAppToggleEnabled = defaults.bool(forKey: Keys.shortcutAppToggleEnabled)
        self.acceptAllKeyAboveTab    = defaults.bool(forKey: Keys.acceptAllKeyAboveTab)
        self.shortcutAlternativesEnabled = defaults.bool(forKey: Keys.shortcutAlternativesEnabled)
        self.midLineCompletion       = defaults.bool(forKey: Keys.midLineCompletion)
        self.alternativesAutoShow    = defaults.bool(forKey: Keys.alternativesAutoShow)
        self.autocorrectStyle        = AutocorrectStyle(
            rawValue: defaults.string(forKey: Keys.autocorrectStyle) ?? "") ?? .inline
        self.recordWritingEnabled    = defaults.bool(forKey: Keys.recordWritingEnabled)
        self.recordWritingMode       = RecordWritingMode(
            rawValue: defaults.string(forKey: Keys.recordWritingMode) ?? "") ?? .acceptedOnly
        self.personalizationStrength = PersonalizationStrength(
            rawValue: defaults.string(forKey: Keys.personalizationStrength) ?? "") ?? .off
        self.syncEnabled             = defaults.bool(forKey: Keys.syncEnabled)
        self.syncIncludePersonalization = defaults.bool(forKey: Keys.syncIncludePersonalization)
        if let raw = defaults.object(forKey: Keys.snoozeUntil) as? Double {
            self.snoozeUntil = Date(timeIntervalSince1970: raw)
        } else {
            self.snoozeUntil = nil
        }
        // Persist firstLaunchDate explicitly on the very first run; didSet
        // doesn't fire during init.
        // `object(forKey:)` returns nil if no real value is stored — unlike
        // `double(forKey:)` which conflates "not stored" with 0. We rely on
        // that to detect first launch.
        if let raw = defaults.object(forKey: Keys.firstLaunchDate) as? Double, raw > 0 {
            self.firstLaunchDate = Date(timeIntervalSince1970: raw)
        } else {
            let now = Date()
            self.firstLaunchDate = now
            defaults.set(now.timeIntervalSince1970, forKey: Keys.firstLaunchDate)
        }

        // One-time migration: turn on the context sources so suggestions are
        // context-aware (clipboard + nearby on-screen text need no permission;
        // screen OCR will prompt for Screen Recording the first time it runs).
        // Guarded by a flag so we never override the user's later choices.
        if !defaults.bool(forKey: Keys.contextMigrationV1) {
            self.clipboardContextEnabled = true
            self.broaderContextEnabled = true
            self.screenContextEnabled = true
            defaults.set(true, forKey: Keys.contextMigrationV1)
        }

        // One-time cleanup: the previous build auto-excluded terminal apps;
        // the user wants autocomplete everywhere, so remove those defaults
        // (leaving any the user added themselves untouched isn't possible to
        // distinguish, but the prior list was empty for affected users).
        if !defaults.bool(forKey: Keys.terminalExclusionRevertV1) {
            let terminals: Set<String> = [
                "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
                "io.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm",
                "co.zeit.hyper", "org.tabby",
            ]
            self.excludedBundleIDs = self.excludedBundleIDs.filter { !terminals.contains($0) }
            defaults.set(true, forKey: Keys.terminalExclusionRevertV1)
        }
    }

    private enum Keys {
        static let isEnabled              = "qalam.isEnabled"
        static let activeModelTag         = "qalam.activeModelTag"
        static let suggestionDelayMs      = "qalam.suggestionDelayMs"
        static let triggerThreshold       = "qalam.triggerThreshold"
        static let excludedBundleIDs      = "qalam.excludedBundleIDs"
        static let hasCompletedOnboarding = "qalam.hasCompletedOnboarding"
        static let launchAtLogin          = "qalam.launchAtLogin"
        static let showInMenuBar          = "qalam.showInMenuBar"
        static let activeModeID           = "qalam.activeModeID"
        static let autoCorrectEnabled     = "qalam.autoCorrectEnabled"
        static let autoGrammarEnabled     = "qalam.autoGrammarEnabled"
        static let maxSuggestionWords     = "qalam.maxSuggestionWords"
        static let firstLaunchDate        = "qalam.firstLaunchDate"
        static let clipboardContextEnabled = "qalam.clipboardContextEnabled"
        static let broaderContextEnabled   = "qalam.broaderContextEnabled"
        static let screenContextEnabled    = "qalam.screenContextEnabled"
        static let engine                  = "qalam.engine"
        static let spaceAfterAccept        = "qalam.spaceAfterAccept"
        static let autoUpdateEnabled       = "qalam.autoUpdateEnabled"
        static let acceptWordKey           = "qalam.acceptWordKey"
        static let showAcceptHint          = "qalam.showAcceptHint"
        static let snoozeUntil             = "qalam.snoozeUntil"
        static let customModelTags         = "qalam.customModelTags"
        static let appearance              = "qalam.appearance"
        static let ghostSizeScale          = "qalam.ghostSizeScale"
        static let ghostVerticalOffset     = "qalam.ghostVerticalOffset"
        static let customInstructions      = "qalam.customInstructions"
        static let caretUnavailableBehavior = "qalam.caretUnavailableBehavior"
        static let showFieldButton         = "qalam.showFieldButton"
        static let escBehavior             = "qalam.escBehavior"
        static let shortcutPauseEnabled    = "qalam.shortcutPauseEnabled"
        static let shortcutForceActivateEnabled = "qalam.shortcutForceActivateEnabled"
        static let shortcutAppToggleEnabled = "qalam.shortcutAppToggleEnabled"
        static let acceptAllKeyAboveTab    = "qalam.acceptAllKeyAboveTab"
        static let shortcutAlternativesEnabled = "qalam.shortcutAlternativesEnabled"
        static let midLineCompletion       = "qalam.midLineCompletion"
        static let alternativesAutoShow    = "qalam.alternativesAutoShow"
        static let autocorrectStyle        = "qalam.autocorrectStyle"
        static let recordWritingEnabled    = "qalam.recordWritingEnabled"
        static let recordWritingMode       = "qalam.recordWritingMode"
        static let personalizationStrength = "qalam.personalizationStrength"
        static let syncEnabled             = "qalam.syncEnabled"
        static let syncIncludePersonalization = "qalam.syncIncludePersonalization"
        static let contextMigrationV1      = "qalam.contextMigrationV1"
        static let terminalExclusionRevertV1 = "qalam.terminalExclusionRevertV1"
    }
}
