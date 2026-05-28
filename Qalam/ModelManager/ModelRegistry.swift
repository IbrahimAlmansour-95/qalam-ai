import Foundation
import SwiftUI

enum ModelSpeed: String, Codable, CaseIterable, Sendable {
    case fast, balanced, quality

    var label: String {
        switch self {
        case .fast:     return "Fast"
        case .balanced: return "Balanced"
        case .quality:  return "Quality"
        }
    }

    var icon: String {
        switch self {
        case .fast:     return "bolt.fill"
        case .balanced: return "scale.3d"
        case .quality:  return "sparkles"
        }
    }

    /// Upper bound on how many words a single suggestion may produce. Bigger /
    /// slower models comfortably stay coherent for longer phrases; smaller
    /// models start to ramble past a few words.
    var maxSuggestionWords: Int {
        switch self {
        case .fast:     return 5
        case .balanced: return 10
        case .quality:  return 15
        }
    }
}

enum ModelFamily: String, Codable, CaseIterable, Sendable {
    case gemma   = "Gemma"
    case qwen    = "Qwen"
    case phi     = "Phi"
    case llama   = "Llama"
    case smollm  = "SmolLM"

    var accent: Color {
        switch self {
        case .gemma:  return QColors.familyGemma
        case .qwen:   return QColors.familyQwen
        case .phi:    return QColors.familyPhi
        case .llama:  return QColors.familyLlama
        case .smollm: return QColors.familySmol
        }
    }
}

struct ModelEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String           // Ollama tag — unique
    let displayName: String
    let family: ModelFamily
    let publisher: String
    let sizeGB: Double
    let ramGB: Double
    let speed: ModelSpeed
    let description: String
    let ollamaTag: String
    let recommended: Bool

    var familyName: String { family.rawValue }
    var maxSuggestionWords: Int { speed.maxSuggestionWords }

    /// True for models with strong multilingual training that includes Arabic.
    /// Surfaced in the Models UI so users writing Arabic pick a capable model.
    /// Curated rather than computed from family because size matters — tiny
    /// models in an otherwise-multilingual family are still poor at Arabic.
    var goodAtArabic: Bool { ModelRegistry.arabicCapableTags.contains(ollamaTag) }
}

enum ModelRegistry {
    /// Models with reliable Arabic generation. Gemma 3/3n/4 (140+ languages)
    /// and Qwen 2.5/3 (29+ languages incl. Arabic) qualify above a minimum
    /// size; the tiniest variants and the English-leaning families (Phi,
    /// Llama 3.x — Arabic isn't in its official language set, SmolLM2) are
    /// excluded so the hint stays trustworthy.
    static let arabicCapableTags: Set<String> = [
        "gemma4:e2b", "gemma4:e4b", "gemma4:26b", "gemma4:31b",
        "gemma3n:e2b", "gemma3n:e4b",
        "gemma3:4b", "gemma3:12b",
        "qwen3:1.7b", "qwen3:4b", "qwen3:8b", "qwen3:30b-a3b",
        "qwen2.5:1.5b", "qwen2.5:3b", "qwen2.5:7b",
    ]

    static let all: [ModelEntry] = [
        // GEMMA 4 — Google (next-gen, ollama.com/library/gemma4)
        ModelEntry(
            id: "gemma4:e2b",
            displayName: "Gemma 4 E2B",
            family: .gemma,
            publisher: "Google",
            sizeGB: 7.2,
            ramGB: 8,
            speed: .balanced,
            description: "Google's newest edge model with 2.3B effective parameters. Recommended default — strongest quality-per-watt for Apple Silicon.",
            ollamaTag: "gemma4:e2b",
            recommended: true
        ),
        ModelEntry(
            id: "gemma4:e4b",
            displayName: "Gemma 4 E4B",
            family: .gemma,
            publisher: "Google",
            sizeGB: 9.6,
            ramGB: 12,
            speed: .balanced,
            description: "Gemma 4 with 4.5B effective parameters (also tagged 'latest'). Higher fidelity for longer-form writing on 16 GB+ Macs.",
            ollamaTag: "gemma4:e4b",
            recommended: false
        ),
        ModelEntry(
            id: "gemma4:26b",
            displayName: "Gemma 4 26B",
            family: .gemma,
            publisher: "Google",
            sizeGB: 18.0,
            ramGB: 24,
            speed: .quality,
            description: "Gemma 4 mixture-of-experts (25.2B params, 3.8B active). Frontier intelligence locally for high-end Macs.",
            ollamaTag: "gemma4:26b",
            recommended: false
        ),
        ModelEntry(
            id: "gemma4:31b",
            displayName: "Gemma 4 31B",
            family: .gemma,
            publisher: "Google",
            sizeGB: 20.0,
            ramGB: 32,
            speed: .quality,
            description: "Dense 30.7B-parameter Gemma 4 for workstation-class Macs. The biggest free-tier Gemma 4.",
            ollamaTag: "gemma4:31b",
            recommended: false
        ),

        // QWEN 3 — Alibaba (latest)
        ModelEntry(
            id: "qwen3:1.7b",
            displayName: "Qwen 3 1.7B",
            family: .qwen,
            publisher: "Alibaba",
            sizeGB: 1.0,
            ramGB: 2,
            speed: .fast,
            description: "Latest Qwen 3 in a compact size. Strong multilingual completions including Arabic.",
            ollamaTag: "qwen3:1.7b",
            recommended: false
        ),
        ModelEntry(
            id: "qwen3:4b",
            displayName: "Qwen 3 4B",
            family: .qwen,
            publisher: "Alibaba",
            sizeGB: 2.3,
            ramGB: 4,
            speed: .balanced,
            description: "Balanced Qwen 3 for everyday writing with strong multilingual reasoning.",
            ollamaTag: "qwen3:4b",
            recommended: false
        ),
        ModelEntry(
            id: "qwen3:8b",
            displayName: "Qwen 3 8B",
            family: .qwen,
            publisher: "Alibaba",
            sizeGB: 4.7,
            ramGB: 8,
            speed: .quality,
            description: "Higher-fidelity Qwen 3 for nuanced long-form content.",
            ollamaTag: "qwen3:8b",
            recommended: false
        ),
        ModelEntry(
            id: "qwen3:30b-a3b",
            displayName: "Qwen 3 30B A3B",
            family: .qwen,
            publisher: "Alibaba",
            sizeGB: 13.7,
            ramGB: 24,
            speed: .quality,
            description: "Flagship Qwen 3 mixture-of-experts. Top-tier quality for high-end Macs.",
            ollamaTag: "qwen3:30b-a3b",
            recommended: false
        ),

        // GEMMA 3n — Google (on-device optimized, MatFormer)
        ModelEntry(
            id: "gemma3n:e2b",
            displayName: "Gemma 3n E2B",
            family: .gemma,
            publisher: "Google",
            sizeGB: 5.6,
            ramGB: 4,
            speed: .fast,
            description: "Google's edge-optimized Gemma 3n with 2B effective parameters. Strong fallback if Gemma 4 isn't available.",
            ollamaTag: "gemma3n:e2b",
            recommended: false
        ),
        ModelEntry(
            id: "gemma3n:e4b",
            displayName: "Gemma 3n E4B",
            family: .gemma,
            publisher: "Google",
            sizeGB: 7.5,
            ramGB: 8,
            speed: .balanced,
            description: "Larger Gemma 3n variant with 4B effective parameters. Higher quality at the cost of more RAM.",
            ollamaTag: "gemma3n:e4b",
            recommended: false
        ),

        // GEMMA 3 — Google (classic)
        ModelEntry(
            id: "gemma3:1b",
            displayName: "Gemma 3 1B",
            family: .gemma,
            publisher: "Google",
            sizeGB: 0.8,
            ramGB: 2,
            speed: .fast,
            description: "Tiny, snappy model for quick edits and short completions on low-memory Macs.",
            ollamaTag: "gemma3:1b",
            recommended: false
        ),
        ModelEntry(
            id: "gemma3:4b",
            displayName: "Gemma 3 4B",
            family: .gemma,
            publisher: "Google",
            sizeGB: 2.5,
            ramGB: 6,
            speed: .balanced,
            description: "Classic Gemma 3 4B — proven, balanced performance for everyday writing.",
            ollamaTag: "gemma3:4b",
            recommended: false
        ),
        ModelEntry(
            id: "gemma3:12b",
            displayName: "Gemma 3 12B",
            family: .gemma,
            publisher: "Google",
            sizeGB: 7.5,
            ramGB: 16,
            speed: .quality,
            description: "Best-in-class quality for longer-form writing. Needs a Mac with 16 GB+.",
            ollamaTag: "gemma3:12b",
            recommended: false
        ),

        // QWEN — Alibaba
        ModelEntry(
            id: "qwen2.5:0.5b",
            displayName: "Qwen 2.5 0.5B",
            family: .qwen,
            publisher: "Alibaba",
            sizeGB: 0.4,
            ramGB: 1,
            speed: .fast,
            description: "Ultra-light. Great for older Macs that still need fast completions.",
            ollamaTag: "qwen2.5:0.5b",
            recommended: false
        ),
        ModelEntry(
            id: "qwen2.5:1.5b",
            displayName: "Qwen 2.5 1.5B",
            family: .qwen,
            publisher: "Alibaba",
            sizeGB: 1.0,
            ramGB: 2,
            speed: .fast,
            description: "Fast multilingual completions with a small footprint.",
            ollamaTag: "qwen2.5:1.5b",
            recommended: false
        ),
        ModelEntry(
            id: "qwen2.5:3b",
            displayName: "Qwen 2.5 3B",
            family: .qwen,
            publisher: "Alibaba",
            sizeGB: 1.9,
            ramGB: 4,
            speed: .balanced,
            description: "Strong multilingual reasoning, balanced for everyday use.",
            ollamaTag: "qwen2.5:3b",
            recommended: false
        ),
        ModelEntry(
            id: "qwen2.5:7b",
            displayName: "Qwen 2.5 7B",
            family: .qwen,
            publisher: "Alibaba",
            sizeGB: 4.7,
            ramGB: 8,
            speed: .quality,
            description: "High-quality completions in 29+ languages, including Arabic.",
            ollamaTag: "qwen2.5:7b",
            recommended: false
        ),

        // PHI — Microsoft
        ModelEntry(
            id: "phi4-mini:3.8b",
            displayName: "Phi 4 Mini",
            family: .phi,
            publisher: "Microsoft",
            sizeGB: 2.5,
            ramGB: 6,
            speed: .balanced,
            description: "Microsoft's compact frontier model — strong reasoning at a small size.",
            ollamaTag: "phi4-mini:3.8b",
            recommended: false
        ),
        ModelEntry(
            id: "phi3:mini",
            displayName: "Phi 3 Mini",
            family: .phi,
            publisher: "Microsoft",
            sizeGB: 2.3,
            ramGB: 4,
            speed: .balanced,
            description: "Battle-tested smaller Phi with great instruction following.",
            ollamaTag: "phi3:mini",
            recommended: false
        ),

        // LLAMA — Meta
        ModelEntry(
            id: "llama3.2:1b",
            displayName: "Llama 3.2 1B",
            family: .llama,
            publisher: "Meta",
            sizeGB: 1.3,
            ramGB: 2,
            speed: .fast,
            description: "Meta's compact Llama, optimized for on-device latency.",
            ollamaTag: "llama3.2:1b",
            recommended: false
        ),
        ModelEntry(
            id: "llama3.2:3b",
            displayName: "Llama 3.2 3B",
            family: .llama,
            publisher: "Meta",
            sizeGB: 2.0,
            ramGB: 4,
            speed: .balanced,
            description: "Solid mid-size Llama for most autocomplete workloads.",
            ollamaTag: "llama3.2:3b",
            recommended: false
        ),
        ModelEntry(
            id: "llama3.1:8b",
            displayName: "Llama 3.1 8B",
            family: .llama,
            publisher: "Meta",
            sizeGB: 4.9,
            ramGB: 10,
            speed: .quality,
            description: "Higher-fidelity Llama for long contexts and nuanced writing.",
            ollamaTag: "llama3.1:8b",
            recommended: false
        ),

        // SMOLLM — HuggingFace
        ModelEntry(
            id: "smollm2:135m",
            displayName: "SmolLM2 135M",
            family: .smollm,
            publisher: "HuggingFace",
            sizeGB: 0.3,
            ramGB: 1,
            speed: .fast,
            description: "The smallest viable model — incredibly fast on any Mac.",
            ollamaTag: "smollm2:135m",
            recommended: false
        ),
        ModelEntry(
            id: "smollm2:360m",
            displayName: "SmolLM2 360M",
            family: .smollm,
            publisher: "HuggingFace",
            sizeGB: 0.7,
            ramGB: 1,
            speed: .fast,
            description: "Tiny model with surprisingly capable short completions.",
            ollamaTag: "smollm2:360m",
            recommended: false
        ),
    ]

    static func entry(forTag tag: String) -> ModelEntry? {
        all.first { $0.ollamaTag == tag || $0.id == tag }
    }

    static func entries(family: ModelFamily?) -> [ModelEntry] {
        guard let family else { return all }
        return all.filter { $0.family == family }
    }

    static func entries(matching query: String) -> [ModelEntry] {
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.familyName.lowercased().contains(q) ||
            $0.publisher.lowercased().contains(q)
        }
    }
}
