import Foundation

struct DeviceSpecs: Sendable, Equatable {
    let ramGB: Double
    let chipName: String        // e.g. "Apple M2 Pro"
    let chipFamily: ChipFamily
    let coreCount: Int

    enum ChipFamily: String, Sendable {
        case m1 = "M1"
        case m2 = "M2"
        case m3 = "M3"
        case m4 = "M4"
        case mUnknown = "Apple Silicon"
        case intel = "Intel"
    }

    var summary: String {
        let ramFmt = ramGB.rounded() == ramGB
            ? "\(Int(ramGB)) GB"
            : String(format: "%.1f GB", ramGB)
        return "\(chipName) · \(ramFmt) RAM · \(coreCount) cores"
    }

    static func detect() -> DeviceSpecs {
        let ram = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let raw = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        return DeviceSpecs(
            ramGB: ram,
            chipName: raw,
            chipFamily: family(from: raw),
            coreCount: cores
        )
    }

    private static func family(from brand: String) -> ChipFamily {
        let s = brand.lowercased()
        if s.contains("m4") { return .m4 }
        if s.contains("m3") { return .m3 }
        if s.contains("m2") { return .m2 }
        if s.contains("m1") { return .m1 }
        if s.contains("apple") { return .mUnknown }
        return .intel
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        if sysctlbyname(name, nil, &size, nil, 0) != 0 || size == 0 { return nil }
        var buf = [CChar](repeating: 0, count: size)
        if sysctlbyname(name, &buf, &size, nil, 0) != 0 { return nil }
        return String(cString: buf)
    }
}

enum ModelRecommender {
    struct Recommendation: Sendable {
        let entry: ModelEntry
        let reason: String
        let alternates: [ModelEntry]
    }

    /// Picks the best model for the user's Mac. Strategy:
    ///   * Reserve ~40% of RAM for the OS + everything else.
    ///   * Prefer the largest Gemma 3n that fits in the remaining budget
    ///     (3n is purpose-built for on-device).
    ///   * Fall back to Gemma 3 / Qwen / SmolLM tiers if 3n doesn't fit.
    static func recommend(for specs: DeviceSpecs) -> Recommendation {
        let budget = specs.ramGB * 0.6

        let preferredOrder = [
            "gemma4:e4b",    // 8 GB RAM  ← largest free-tier sweet spot
            "gemma4:e2b",    // 4 GB RAM  ← default for 16 GB Macs
            "gemma3n:e4b",
            "gemma3n:e2b",
            "qwen3:4b",
            "qwen3:1.7b",
            "qwen2.5:3b",
            "gemma3:4b",
            "llama3.2:3b",
            "qwen2.5:1.5b",
            "gemma3:1b",
            "llama3.2:1b",
            "qwen2.5:0.5b",
            "smollm2:360m",
            "smollm2:135m",
        ]
        var chosen: ModelEntry?
        for tag in preferredOrder {
            guard let entry = ModelRegistry.entry(forTag: tag) else { continue }
            if entry.ramGB <= budget {
                chosen = entry
                break
            }
        }
        let entry = chosen ?? ModelRegistry.entry(forTag: "smollm2:135m")!

        let reason = makeReason(for: entry, specs: specs, budget: budget)

        // Up to 3 alternates: one notch lighter (faster) and one notch heavier (better) if available.
        let alternates = pickAlternates(around: entry, specs: specs, budget: budget)

        return Recommendation(entry: entry, reason: reason, alternates: alternates)
    }

    private static func makeReason(for entry: ModelEntry,
                                   specs: DeviceSpecs,
                                   budget: Double) -> String {
        let chip = specs.chipFamily.rawValue
        let ram = Int(specs.ramGB.rounded())
        if entry.ollamaTag.hasPrefix("gemma4") {
            return "\(chip) with \(ram) GB RAM comfortably runs Gemma 4 — Google's newest edge model. Best quality-per-watt for your Mac."
        }
        if entry.ollamaTag.hasPrefix("gemma3n") {
            return "\(chip) with \(ram) GB RAM runs Gemma 3n — Google's edge-optimized model designed for Apple Silicon."
        }
        if entry.speed == .fast {
            return "With \(ram) GB RAM, a lightweight model keeps suggestions instant. You can upgrade to a larger one later."
        }
        return "Balanced choice for your Mac (\(ram) GB RAM, \(chip)). Strong quality without taxing the system."
    }

    private static func pickAlternates(around chosen: ModelEntry,
                                       specs: DeviceSpecs,
                                       budget: Double) -> [ModelEntry] {
        let fitting = ModelRegistry.all.filter { $0.ramGB <= budget && $0.ollamaTag != chosen.ollamaTag }
        let smaller = fitting
            .filter { $0.ramGB < chosen.ramGB }
            .max(by: { $0.ramGB < $1.ramGB })
        let larger = fitting
            .filter { $0.ramGB > chosen.ramGB }
            .min(by: { $0.ramGB < $1.ramGB })
        return [smaller, larger].compactMap { $0 }
    }
}
