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
        lines.append("Max words:        \(prefs.maxSuggestionWords)")
        lines.append("Trigger delay:    \(prefs.suggestionDelayMs) ms")
        lines.append("Autocorrect:      \(prefs.autoCorrectEnabled)")
        lines.append("Grammar:          \(prefs.autoGrammarEnabled)")
        lines.append("Clipboard ctx:    \(prefs.clipboardContextEnabled)")
        lines.append("Broader ctx:      \(prefs.broaderContextEnabled)")
        lines.append("Screen ctx:       \(prefs.screenContextEnabled)")
        lines.append("Excluded apps:    \(prefs.excludedBundleIDs.count)")
        lines.append("Launch at login:  \(prefs.launchAtLogin)")
        lines.append("Auto-update:      \(prefs.autoUpdateEnabled)")
        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(report(), forType: .string)
    }
}
