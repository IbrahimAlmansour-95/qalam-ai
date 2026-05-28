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
        didSet { defaults.set(activeModelTag, forKey: Keys.activeModelTag) }
    }
    var suggestionDelayMs: Int {
        didSet { defaults.set(suggestionDelayMs, forKey: Keys.suggestionDelayMs) }
    }
    var triggerThreshold: Int {
        didSet { defaults.set(triggerThreshold, forKey: Keys.triggerThreshold) }
    }
    var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs) }
    }
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
    }
}
