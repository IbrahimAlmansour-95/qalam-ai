import Foundation

struct Snippet: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var trigger: String        // typed token without the leading colon, e.g. "sig"
    var expansion: String

    init(id: String = UUID().uuidString, trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

@MainActor
@Observable
final class SnippetStore {
    static let shared = SnippetStore()

    private let key = "qalam.snippets"
    private(set) var snippets: [Snippet] = []

    private init() {
        load()
        if snippets.isEmpty {
            // Seed with helpful defaults so the feature is discoverable.
            snippets = [
                Snippet(trigger: "sig",   expansion: "— \(Constants.developer)\nSent from \(Constants.appName)"),
                Snippet(trigger: "addr",  expansion: "(your address here)"),
                Snippet(trigger: "thx",   expansion: "Thanks so much — really appreciate it."),
                Snippet(trigger: "ty",    expansion: "Thanks!"),
                Snippet(trigger: "ack",   expansion: "Got it, will take a look."),
            ]
            save()
        }
    }

    /// Snapshot for use off the main actor (e.g. inside SuggestionEngine streams).
    nonisolated func snapshot() -> [Snippet] {
        // Re-decode from defaults rather than touching @Observable state from
        // a nonisolated context.
        guard let data = QalamDefaults.suite.data(forKey: "qalam.snippets"),
              let list = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return [] }
        return list
    }

    func add(trigger: String, expansion: String) {
        let cleaned = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !cleaned.isEmpty else { return }
        snippets.removeAll { $0.trigger == cleaned }
        snippets.append(Snippet(trigger: cleaned, expansion: expansion))
        save()
    }

    func update(_ snippet: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
            save()
        }
    }

    func delete(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    func match(trigger: String) -> Snippet? {
        let key = trigger.lowercased()
        return snippets.first { $0.trigger == key }
    }

    private func load() {
        if let data = QalamDefaults.suite.data(forKey: key),
           let list = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snippets) {
            QalamDefaults.suite.set(data, forKey: key)
        }
    }
}
