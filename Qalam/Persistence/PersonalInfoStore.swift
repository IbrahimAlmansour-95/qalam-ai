import Foundation
import Observation

/// One piece of personal info the user wants QalamAI to know, so it can
/// complete it in context (e.g. typing "reach me at " → their email).
struct PersonalInfoItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var label: String      // e.g. "Name", "Work email", "Phone"
    var value: String      // e.g. "Ibrahim Almansour", "ibrahim@almansour.com"

    init(id: String = UUID().uuidString, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

/// Local-only vault of the user's details. Persisted to our defaults suite,
/// never transmitted — it's fed straight into the on-device prompt.
@MainActor
@Observable
final class PersonalInfoStore {
    static let shared = PersonalInfoStore()

    private let key = "qalam.personalInfo"
    private(set) var items: [PersonalInfoItem] = []

    private init() {
        load()
        if items.isEmpty {
            // Seed with empty common fields so the feature is discoverable.
            items = [
                PersonalInfoItem(label: "Name", value: ""),
                PersonalInfoItem(label: "Email", value: ""),
                PersonalInfoItem(label: "Phone", value: ""),
            ]
            save()
        }
    }

    func add(label: String = "", value: String = "") {
        items.append(PersonalInfoItem(label: label, value: value))
        save()
    }

    func update(_ item: PersonalInfoItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
            save()
        }
    }

    func delete(_ item: PersonalInfoItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// A compact, prompt-ready block of the filled-in fields. Returns "" when
    /// nothing useful is set. Off the main actor friendly via snapshot read.
    nonisolated func promptBlock() -> String {
        guard let data = QalamDefaults.suite.data(forKey: "qalam.personalInfo"),
              let list = try? JSONDecoder().decode([PersonalInfoItem].self, from: data)
        else { return "" }
        let lines = list
            .filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty &&
                      !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\($0.label): \($0.value)" }
        return lines.joined(separator: "\n")
    }

    private func load() {
        if let data = QalamDefaults.suite.data(forKey: key),
           let list = try? JSONDecoder().decode([PersonalInfoItem].self, from: data) {
            items = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            QalamDefaults.suite.set(data, forKey: key)
        }
    }
}
