import Foundation
import SwiftUI

struct WritingMode: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var iconSymbol: String
    var instruction: String      // appended to the system prompt
    var temperature: Double      // overrides default sampling temperature
    var isBuiltIn: Bool

    static let neutral = WritingMode(
        id: "neutral",
        name: "Neutral",
        iconSymbol: "circle.dotted",
        instruction: "Continue the text naturally in the user's existing tone.",
        temperature: 0.30,
        isBuiltIn: true
    )

    static let professional = WritingMode(
        id: "professional",
        name: "Professional",
        iconSymbol: "briefcase",
        instruction: "Write in a clear, concise, professional tone. Avoid contractions and slang. Prefer precise vocabulary.",
        temperature: 0.20,
        isBuiltIn: true
    )

    static let casual = WritingMode(
        id: "casual",
        name: "Casual",
        iconSymbol: "bubble.left.and.bubble.right",
        instruction: "Write in a warm, conversational tone. Contractions are welcome. Keep sentences short.",
        temperature: 0.40,
        isBuiltIn: true
    )

    static let code = WritingMode(
        id: "code",
        name: "Code",
        iconSymbol: "chevron.left.forwardslash.chevron.right",
        instruction: "Complete code idiomatically. Match the surrounding style, indentation, and naming. Do not invent APIs.",
        temperature: 0.10,
        isBuiltIn: true
    )

    static let email = WritingMode(
        id: "email",
        name: "Email",
        iconSymbol: "envelope",
        instruction: "Write as if composing an email. Polite, concise, structured. Use clear paragraph breaks at natural beats.",
        temperature: 0.25,
        isBuiltIn: true
    )

    static let reply = WritingMode(
        id: "reply",
        name: "Reply",
        iconSymbol: "arrowshape.turn.up.left",
        instruction: "Write a thoughtful direct reply. Acknowledge the prior message in tone and content, then advance the conversation.",
        temperature: 0.30,
        isBuiltIn: true
    )

    static let builtIns: [WritingMode] = [
        .neutral, .professional, .casual, .code, .email, .reply
    ]
}

@MainActor
@Observable
final class WritingModeStore {
    static let shared = WritingModeStore()

    private let key = "qalam.writingModes.custom"
    private(set) var customModes: [WritingMode] = []

    var allModes: [WritingMode] {
        WritingMode.builtIns + customModes
    }

    private init() {
        load()
    }

    func mode(id: String) -> WritingMode {
        allModes.first(where: { $0.id == id }) ?? .neutral
    }

    func add(name: String, instruction: String, iconSymbol: String = "sparkles", temperature: Double = 0.3) {
        let m = WritingMode(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: name,
            iconSymbol: iconSymbol,
            instruction: instruction,
            temperature: temperature,
            isBuiltIn: false
        )
        customModes.append(m)
        save()
    }

    func update(_ mode: WritingMode) {
        guard !mode.isBuiltIn,
              let idx = customModes.firstIndex(where: { $0.id == mode.id })
        else { return }
        customModes[idx] = mode
        save()
    }

    func delete(_ mode: WritingMode) {
        guard !mode.isBuiltIn else { return }
        customModes.removeAll { $0.id == mode.id }
        save()
    }

    private func load() {
        guard let data = QalamDefaults.suite.data(forKey: key) else { return }
        if let list = try? JSONDecoder().decode([WritingMode].self, from: data) {
            customModes = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(customModes) {
            QalamDefaults.suite.set(data, forKey: key)
        }
    }
}
