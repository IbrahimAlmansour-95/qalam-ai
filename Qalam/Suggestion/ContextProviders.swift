import Foundation
import AppKit

/// Reads recent clipboard text to feed the model as extra context. Opt-in
/// (privacy-sensitive) and bounded. Never reads non-text pasteboard items.
enum ClipboardContextProvider {
    static func recentText(maxChars: Int = 1_000) -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        return String(trimmed.prefix(maxChars))
    }
}
