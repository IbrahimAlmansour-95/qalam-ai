import Foundation

// MARK: - Per-app / per-site settings

/// How suggestions start in an app or on a site. `nil` on a profile = inherit.
enum ProfileActivation: String, Codable, CaseIterable, Sendable {
    /// Suggest automatically, skipping the automatic idle rules.
    case alwaysOn
    /// No automatic suggestions; only the force-activate shortcut (T4).
    case forceOnly
    /// Never suggest.
    case off
}

/// Where the suggestion is drawn. `mirror` is the bubble added by T5.
enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case inline, mirror
}

/// Which language suggestions are offered for.
enum LanguagePreference: String, Codable, CaseIterable, Sendable {
    case auto, english, arabic
}

/// Settings for one app (keyed by bundle id) or one website (keyed by its
/// normalized host). Every optional field is "inherit": `nil` falls back to
/// the matching site → app → global value (see `ProfileStore.resolve`).
struct AppProfile: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case app, domain }

    var id: String                 // "app:<bundleID>" | "domain:<host>"
    var kind: Kind
    var key: String                // bundle id, or normalized host
    var displayName: String

    // nil = inherit
    var activation: ProfileActivation?
    var displayMode: DisplayMode?          // wired by T5 (mirror bubble)
    var tabAcceptEnabled: Bool?            // wired by T4 (per-app Tab)
    var customInstructions: String?
    var writingModeId: String?
    var languagePreference: LanguagePreference?
    var recordWriting: Bool?               // wired by T6 (personalization)
    var improveCompatibility: Bool?        // wired by T5 (apps only)
    var autocorrectEnabled: Bool?

    var lastSeen: Date
    /// Set on every user edit (used by sync in T8). `lastSeen` bookkeeping
    /// never touches it.
    var modifiedAt: Date

    /// True when any setting differs from "inherit". Unconfigured app
    /// profiles are the "Recently seen" list; unconfigured site profiles are
    /// never written to disk.
    var isConfigured: Bool {
        activation != nil || displayMode != nil || tabAcceptEnabled != nil
            || !(customInstructions ?? "").isEmpty || writingModeId != nil
            || languagePreference != nil || recordWriting != nil
            || improveCompatibility != nil || autocorrectEnabled != nil
    }

    static func appID(_ bundleID: String) -> String { "app:\(bundleID)" }
    static func domainID(_ host: String) -> String { "domain:\(host)" }

    /// An unconfigured app profile. `modifiedAt` stays `.distantPast` until
    /// the user edits it (being seen is not an edit).
    static func newApp(bundleID: String, name: String, lastSeen: Date) -> AppProfile {
        AppProfile(id: appID(bundleID), kind: .app, key: bundleID, displayName: name,
                   lastSeen: lastSeen, modifiedAt: .distantPast)
    }

    static func newDomain(host: String, lastSeen: Date) -> AppProfile {
        AppProfile(id: domainID(host), kind: .domain, key: host, displayName: host,
                   lastSeen: lastSeen, modifiedAt: .distantPast)
    }

    /// Clears every setting back to "inherit".
    mutating func resetToInherit() {
        activation = nil
        displayMode = nil
        tabAcceptEnabled = nil
        customInstructions = nil
        writingModeId = nil
        languagePreference = nil
        recordWriting = nil
        improveCompatibility = nil
        autocorrectEnabled = nil
    }
}

extension AppProfile {
    private enum CodingKeys: String, CodingKey {
        case id, kind, key, displayName, activation, displayMode, tabAcceptEnabled,
             customInstructions, writingModeId, languagePreference, recordWriting,
             improveCompatibility, autocorrectEnabled, lastSeen, modifiedAt
    }

    /// Lenient decoding: an enum value this build doesn't know (written by a
    /// newer version) reads as "inherit" instead of failing the whole list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        key = try c.decode(String.self, forKey: .key)
        displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? key
        activation = (try? c.decodeIfPresent(String.self, forKey: .activation)).flatMap { ProfileActivation(rawValue: $0) }
        displayMode = (try? c.decodeIfPresent(String.self, forKey: .displayMode)).flatMap { DisplayMode(rawValue: $0) }
        tabAcceptEnabled = try? c.decodeIfPresent(Bool.self, forKey: .tabAcceptEnabled)
        customInstructions = try? c.decodeIfPresent(String.self, forKey: .customInstructions)
        writingModeId = try? c.decodeIfPresent(String.self, forKey: .writingModeId)
        languagePreference = (try? c.decodeIfPresent(String.self, forKey: .languagePreference)).flatMap { LanguagePreference(rawValue: $0) }
        recordWriting = try? c.decodeIfPresent(Bool.self, forKey: .recordWriting)
        improveCompatibility = try? c.decodeIfPresent(Bool.self, forKey: .improveCompatibility)
        autocorrectEnabled = try? c.decodeIfPresent(Bool.self, forKey: .autocorrectEnabled)
        lastSeen = (try? c.decodeIfPresent(Date.self, forKey: .lastSeen)) ?? .distantPast
        modifiedAt = (try? c.decodeIfPresent(Date.self, forKey: .modifiedAt)) ?? .distantPast
    }
}

// MARK: - Resolution result

enum ResolvedActivation: Sendable, Equatable {
    /// No profile says otherwise (global default).
    case automatic, alwaysOn, forceOnly, off
}

/// The effective settings for one app (+ site). Built by
/// `ProfileStore.resolve`: site profile > app profile > global default, per
/// field.
struct ResolvedProfile: Sendable, Equatable {
    let bundleID: String?
    let host: String?
    let activation: ResolvedActivation     // global = .automatic
    let displayMode: DisplayMode           // global = .inline
    let tabAcceptEnabled: Bool             // global = true
    /// Global + app + site instructions (non-empty parts, newline-joined).
    let customInstructions: String
    let writingModeID: String              // global = prefs.activeModeID
    let languagePreference: LanguagePreference   // global = .auto
    let recordWriting: Bool                // global = !KnownApps.isTerminal(bundleID)
    /// The app profile's own value (nil = never set → T5 may auto-attempt).
    let improveCompatibility: Bool?
    let autocorrectEnabled: Bool           // global = prefs.autoCorrectEnabled
    let temporarilyPausedUntil: Date?      // TemporaryPauseStore

    var isTemporarilyPaused: Bool {
        temporarilyPausedUntil.map { $0 > Date() } ?? false
    }
}

/// The last app (other than QalamAI) the user was in — for the menu bar
/// quick toggle and "Add frontmost app".
struct ExternalAppRef: Equatable, Sendable {
    let bundleID: String
    let name: String
    let pid: pid_t
}

// MARK: - Known app families

enum KnownApps {
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "company.thebrowser.Browser", "company.thebrowser.dia",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    private static let firefoxFamily: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
    ]

    /// Browsers whose page content reliably sits under an `AXWebArea`
    /// (everything but the Firefox family).
    static let webAreaReliableBrowsers: Set<String> = browsers.subtracting(firefoxFamily)

    /// Same list as the terminal-exclusion revert in `UserPreferences.init`,
    /// plus Ghostty. Only used for defaults that should be conservative in a
    /// terminal (e.g. recording writing samples) — suggestions stay on.
    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "io.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm",
        "co.zeit.hyper", "org.tabby", "com.mitchellh.ghostty",
    ]

    /// Editors whose default key bindings collide with BOTH of our global
    /// shortcuts (⌃` toggles the terminal / the console, ⇧⌘Space = parameter
    /// hints in VS Code and "expand selection to scope" in Sublime Text).
    /// The Electron ones also switch into "screen reader optimized" mode when
    /// AXManualAccessibility is set. Suggestions are NOT idled here.
    static let shortcutReservedEditors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.visualstudio.code.oss", "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf", "dev.zed.Zed", "dev.zed.Zed-Preview",
        "com.sublimetext.4", "com.sublimetext.3", "com.sublimetext.2",
    ]

    /// Password managers, plus Apple's Passwords and Keychain Access. Screen
    /// context never captures while one of these is being typed in. The
    /// third-party ids are the ones macOS's own Passwords import list names;
    /// the vendor prefixes cover their other builds (1Password 7/8 and
    /// betas, Dashlane's older app, Enpass, Proton Pass's desktop app), also
    /// behind a Team ID (1Password 7 mini). Lowercased: bundle ids compare
    /// case-insensitively.
    private static let passwordManagers: Set<String> = [
        "com.apple.passwords", "com.apple.keychainaccess",
        "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "com.lastpass.lastpass", "com.dashlane.dashlanephonefinal",
        "org.keepassxc.keepassxc", "com.markmcguill.strongbox", "me.proton.pass.ios",
        "com.kaspersky.kpm", "com.romainp.se-same", "com.outercorner.secrets",
        "com.sibersystems.roboformmac", "com.keepersecurity.safari.keeperfill",
        "com.callpod.keepermac.lite", "com.keepsolid.passwarden",
        "com.safeincloud.safe-in-cloud.osx", "ca.jeffreyfulton.minipass", "com.mseven.msecuremac",
    ]

    private static let passwordManagerPrefixes: [String] = [
        "com.apple.passwords.", "com.1password.", "com.agilebits.", "com.bitwarden.",
        "com.lastpass.", "com.dashlane.", "in.sinew.", "org.keepassxc.",
        "com.markmcguill.strongbox", "me.proton.pass.",
    ]

    static func isPasswordManager(_ id: String?) -> Bool {
        guard let id = id?.lowercased() else { return false }
        func matches(_ s: String) -> Bool {
            passwordManagers.contains(s) || passwordManagerPrefixes.contains { s.hasPrefix($0) }
        }
        if matches(id) { return true }
        // Helpers carrying a Team ID prefix, e.g. 1Password 7 mini
        // ("2BUA8C4S2C.com.agilebits.onepassword7-helper").
        if let dot = id.firstIndex(of: "."), id.distance(from: id.startIndex, to: dot) == 10,
           id[..<dot].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return matches(String(id[id.index(after: dot)...]))
        }
        return false
    }

    /// System panels that show other apps' content: Notification Center
    /// (banners, inline replies) and Spotlight (result previews). Screen
    /// context never captures while one of these is being typed in.
    /// Lowercased.
    private static let otherAppsContentPanels: Set<String> = [
        "com.apple.notificationcenterui", "com.apple.spotlight",
    ]

    static func showsOtherAppsContent(_ id: String?) -> Bool {
        guard let id = id?.lowercased() else { return false }
        return otherAppsContentPanels.contains(id)
    }

    static func isBrowser(_ id: String?) -> Bool {
        guard let id else { return false }
        return browsers.contains(id)
    }

    static func isTerminal(_ id: String?) -> Bool {
        guard let id else { return false }
        return terminals.contains(id)
    }

    static func isShortcutReservedEditor(_ id: String?) -> Bool {
        guard let id else { return false }
        return shortcutReservedEditors.contains(id)
    }

    /// Apps that ⌃ + the key above Tab is left to. A superset of
    /// `shortcutReservedEditors`: the JetBrains IDEs bind ⌃` to "Quick Switch
    /// Scheme" in the stock macOS keymap, but they do not bind ⇧⌘Space, so
    /// only the "Suggest now" shortcut defers to them — global pause keeps
    /// working there. Suggestions are NOT idled in any of these; a user who
    /// wants ⌃` back as the request key sets that app to "Force only".
    ///
    /// Prefix matches so the `.ce`, EAP and Toolbox variants are covered
    /// without another edit (com.jetbrains.intellij, .pycharm, .WebStorm,
    /// .PhpStorm, .goland, .CLion, .rider, .rubymine, .datagrip, .fleet …).
    static func isForceShortcutReserved(_ id: String?) -> Bool {
        guard let id else { return false }
        return isShortcutReservedEditor(id)
            || id.hasPrefix("com.jetbrains.")
            || id.hasPrefix("com.google.android.studio")
    }
}
