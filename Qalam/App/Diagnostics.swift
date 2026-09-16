import Foundation
import AppKit

/// Gathers a privacy-safe snapshot of app + system state for troubleshooting.
/// Deliberately excludes anything the user has typed, their snippets, or the
/// personal-info vault — only configuration and runtime status.
@MainActor
enum Diagnostics {
    static func report() -> String {
        let prefs = UserPreferences.shared
        let mm = ModelManager.shared
        let ax = AccessibilityPermissionMonitor.shared

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"

        let ollama: String
        switch mm.ollamaState {
        case .running:      ollama = "running"
        case .starting:     ollama = "starting"
        case .stopped:      ollama = "stopped"
        case .notInstalled: ollama = "not installed"
        case .unknown:      ollama = "unknown"
        }

        var lines: [String] = []
        lines.append("QalamAI Diagnostics")
        lines.append("===================")
        lines.append("App version:      \(Constants.version)")
        lines.append("Bundle ID:        \(Constants.bundleID)")
        lines.append("macOS:            \(osString)")
        lines.append("Architecture:     arm64")
        lines.append("Detected RAM:     \(String(format: "%.0f GB", mm.detectedRAMGB))")
        lines.append("")
        lines.append("Accessibility:    \(ax.isGranted ? "granted" : "NOT granted")")
        lines.append("Engine:           \(prefs.engine)")
        lines.append("Ollama state:     \(ollama)")
        lines.append("Active model:     \(prefs.activeModelTag)")
        lines.append("Installed models: \(mm.installedTags.sorted().joined(separator: ", "))")
        lines.append("Custom models:    \(prefs.customModelTags.joined(separator: ", "))")
        lines.append("")
        lines.append("Suggestions:      \(prefs.isEnabled ? "enabled" : "disabled")\(prefs.isSnoozed ? " (snoozed)" : "")")
        lines.append("Accept key:       \(prefs.acceptWordKey)")
        let modelMax = ModelRegistry.entry(forTag: prefs.activeModelTag)?.maxSuggestionWords ?? 5
        let lengthPreset = CompletionLength.from(
            words: max(1, min(prefs.maxSuggestionWords, modelMax)), modelMax: modelMax)
        lines.append("Max words:        \(prefs.maxSuggestionWords) (\(lengthPreset.rawValue), model cap \(modelMax))")
        lines.append("Trigger delay:    \(prefs.suggestionDelayMs) ms")
        lines.append("Autocorrect:      \(prefs.autoCorrectEnabled)")
        lines.append("Grammar:          \(prefs.autoGrammarEnabled)")
        lines.append("Clipboard ctx:    \(prefs.clipboardContextEnabled)")
        lines.append("Broader ctx:      \(prefs.broaderContextEnabled)")
        lines.append("Screen ctx:       \(prefs.screenContextEnabled)")
        // Counts only — never app names, hosts or instruction text.
        let profiles = ProfileStore.shared
        lines.append("Profiles:         \(profiles.configuredAppCount) apps, \(profiles.configuredSiteCount) sites; migrated exclusions: \(profiles.didMigrateExclusions ? "yes" : "no")")
        lines.append("Custom instr.:    \(prefs.customInstructions.isEmpty ? "empty" : "set (\(prefs.customInstructions.count) chars)")")
        lines.append("No-caret display: \(prefs.caretUnavailableBehavior.rawValue)")
        lines.append("Field button:     \(prefs.showFieldButton ? "on" : "off")")
        lines.append("Esc behaviour:    \(prefs.escBehavior.rawValue)")
        lines.append("Shortcuts:        pause \(prefs.shortcutPauseEnabled ? "on" : "off"), suggest now \(prefs.shortcutForceActivateEnabled ? "on" : "off"), app pause \(prefs.shortcutAppToggleEnabled ? "on" : "off"), alternatives \(prefs.shortcutAlternativesEnabled ? "on" : "off"), accept-all above Tab \(prefs.acceptAllKeyAboveTab ? "on" : "off")")
        lines.append("Mid-line:         \(prefs.midLineCompletion ? "on" : "off")")
        lines.append("Fix style:        \(prefs.autocorrectStyle.rawValue)")
        lines.append("Alternatives:     auto-show \(prefs.alternativesAutoShow ? "on" : "off")")
        // Counts only — never a word of what was recorded.
        let personal = PersonalizationSnapshot.shared
        let sampleCount = personal.isLoaded ? "\(personal.sampleCount)"
            : (personal.isUnavailable ? "unavailable" : "not loaded")
        lines.append("Personalization:  recording \(prefs.recordWritingEnabled ? "on" : "off"), mode \(prefs.recordWritingMode.rawValue), strength \(prefs.personalizationStrength.rawValue), samples: \(sampleCount)")
        // Status and timing only — never a file path or a key.
        let sync: String
        if prefs.syncEnabled {
            let last = SyncManager.shared.lastSyncAt.map {
                $0.formatted(Date.ISO8601FormatStyle(timeZone: .current))
            } ?? "never"
            sync = "on (\(Self.syncStatusText(SyncManager.shared.status))), last sync \(last)"
        } else {
            sync = "off"
        }
        lines.append("Sync:             \(sync), include samples \(prefs.syncIncludePersonalization ? "yes" : "no")")
        lines.append("Launch at login:  \(prefs.launchAtLogin)")
        lines.append("Auto-update:      \(prefs.autoUpdateEnabled)")
        lines.append("")

        let supervisor: String
        switch mm.engineSupervisor {
        case .idle:                        supervisor = "idle"
        case .restarting(let attempt):     supervisor = "restarting(\(attempt))"
        case .failed:                      supervisor = "failed"
        }
        let backoffs = AXGuard.activeBackoffCount()
        lines.append("Engine supervisor: \(supervisor)")
        lines.append("Secure Input:     \(SecureInputMonitor.shared.isActive ? "on" : "off")")
        lines.append("AX backoff active: \(backoffs > 0 ? "yes (\(backoffs) app\(backoffs == 1 ? "" : "s"))" : "no")")
        if let crash = DiagnosticsCollector.lastCrashSummary() {
            let when = crash.date.formatted(Date.ISO8601FormatStyle(timeZone: .current))
            lines.append("Last crash:       \(when) \(crash.kind) \(crash.detail)")
        } else {
            lines.append("Last crash:       none")
        }
        lines.append("")
        // The file log holds only static text and non-user values (QLog's
        // contract), so its tail is safe to share.
        let recent = QLog.recentFileLines(40)
        lines.append("Recent log (last 40 lines):")
        lines.append(contentsOf: recent.isEmpty ? ["(empty)"] : recent)
        return lines.joined(separator: "\n")
    }

    private static func syncStatusText(_ status: SyncManager.Status) -> String {
        switch status {
        case .off:                return "off"
        case .unavailable:        return "iCloud Drive unavailable"
        case .idle:               return "idle"
        case .syncing:            return "syncing"
        case .waitingForDownload: return "waiting for download"
        case .error(let kind):    return "error: \(kind)"
        }
    }

    /// Opens ~/Library/Logs/QalamAI (rotating log + local crash diagnostics)
    /// in Finder.
    static func revealLogs() {
        let dir = QLog.logDirectory
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } else {
            NSWorkspace.shared.open(dir.deletingLastPathComponent())
        }
    }

    static func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(report(), forType: .string)
    }
}
