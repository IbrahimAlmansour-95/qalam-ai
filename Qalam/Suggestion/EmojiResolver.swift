import Foundation

/// Resolves ":name:" style shortcodes to emoji glyphs.
struct EmojiResolver: Sendable {
    private let map: [String: String]

    init(map: [String: String]) {
        self.map = map
    }

    static let `default`: EmojiResolver = {
        if let url = Bundle.main.url(forResource: "emoji-shortcodes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return EmojiResolver(map: dict)
        }
        return EmojiResolver(map: [
            "smile": "🙂",
            "fire": "🔥",
            "rocket": "🚀",
            "tada": "🎉",
            "thumbsup": "👍",
            "heart": "❤️",
            "star": "⭐",
            "check": "✅",
            "x": "❌",
            "warning": "⚠️",
        ])
    }()

    func resolve(_ token: String) -> String? {
        guard token.hasPrefix(":"), token.hasSuffix(":"), token.count > 2 else { return nil }
        let key = String(token.dropFirst().dropLast())
        return map[key]
    }

    /// Prefix-match for inline emoji suggestions. Given a typed partial like
    /// "smi" (no colons), returns the first emoji whose shortcode starts with
    /// it, alongside the canonical shortcode.
    func bestPrefixMatch(for partial: String) -> (shortcode: String, glyph: String)? {
        let needle = partial.lowercased()
        guard !needle.isEmpty else { return nil }
        // Sort keys so the prefix match is stable.
        let candidates = map.keys.sorted()
        if let exact = map[needle] {
            return (needle, exact)
        }
        for code in candidates where code.hasPrefix(needle) {
            if let g = map[code] { return (code, g) }
        }
        return nil
    }
}
