import Foundation

enum Constants {
    static let appName = "QalamAI"
    static let bundleID = "com.qalamai.app"
    static let developer = "Ibrahim Almansour"
    static let version = "1.0.0"

    /// Subdirectory under ~/Library/Application Support used for installer
    /// downloads, runtime state, etc.
    static let appSupportDirName = "QalamAI"

    enum Ollama {
        static let host = "127.0.0.1"
        static let port = 11434
        static let baseURL = URL(string: "http://127.0.0.1:11434")!
        static let tagsURL = URL(string: "http://127.0.0.1:11434/api/tags")!
        static let generateURL = URL(string: "http://127.0.0.1:11434/api/generate")!
        static let deleteURL = URL(string: "http://127.0.0.1:11434/api/delete")!
        static let installURL = URL(string: "https://ollama.ai")!
        static let healthCheckInterval: TimeInterval = 10
    }

    enum Suggestion {
        // 120 ms is the sweet spot Cotypist targets too — "updates within a
        // letter or two" — fast enough to feel native, slow enough not to
        // hammer the local model on every keystroke.
        static let defaultDelayMs = 120
        static let defaultTriggerThreshold = 2
        static let maxContextChars = 800
        // SuggestionEngine computes a per-suggestion budget from
        // user.maxSuggestionWords; this is a hard upper bound.
        static let maxTokens = 30
        static let temperature: Double = 0.3
        static let ghostFadeInMs = 60
    }

    enum URLs {
        static let homepage = URL(string: "https://qalam.app")!
        static let support = URL(string: "https://qalam.app/support")!
    }
}
