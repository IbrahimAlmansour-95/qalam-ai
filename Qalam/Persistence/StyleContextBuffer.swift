import Foundation

actor StyleContextBuffer {
    static let shared = StyleContextBuffer()

    private let key = "qalam.styleContext.entries"
    private let maxEntries = 50
    private var entries: [String]

    private init() {
        self.entries = (QalamDefaults.suite.array(forKey: key) as? [String]) ?? []
    }

    func append(_ phrase: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.append(trimmed)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    func recentContext(maxChars: Int = 400) -> String {
        var out = ""
        for entry in entries.reversed() {
            let candidate = entry + (out.isEmpty ? "" : " ") + out
            if candidate.count > maxChars { break }
            out = candidate
        }
        return out
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func count() -> Int { entries.count }

    private func persist() {
        QalamDefaults.suite.set(entries, forKey: key)
    }
}
