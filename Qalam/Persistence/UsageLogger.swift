import Foundation

actor UsageLogger {
    static let shared = UsageLogger()

    private enum Keys {
        static let wordsCompletedToday = "qalam.usage.wordsCompletedToday"
        static let keystrokesSaved     = "qalam.usage.keystrokesSaved"
        static let suggestionsShown    = "qalam.usage.suggestionsShown"
        static let lastResetDay        = "qalam.usage.lastResetDay"
        static let history             = "qalam.usage.history"   // [String: Int] (day key → words)
    }

    private var wordsCompletedToday: Int = 0
    private var keystrokesSaved: Int = 0
    private var suggestionsShown: Int = 0
    private var lastResetDay: Int = 0
    /// Rolling per-day word totals. Keys are "YYYY-MM-DD".
    private var history: [String: Int] = [:]

    private init() {
        let d = QalamDefaults.suite
        self.wordsCompletedToday = d.integer(forKey: Keys.wordsCompletedToday)
        self.keystrokesSaved     = d.integer(forKey: Keys.keystrokesSaved)
        self.suggestionsShown    = d.integer(forKey: Keys.suggestionsShown)
        self.lastResetDay        = d.integer(forKey: Keys.lastResetDay)
        self.history             = (d.dictionary(forKey: Keys.history) as? [String: Int]) ?? [:]
    }

    struct Snapshot: Sendable {
        let wordsCompletedToday: Int
        let keystrokesSaved: Int
        let suggestionsShown: Int
    }

    func snapshot() -> Snapshot {
        rolloverIfNeeded()
        return Snapshot(
            wordsCompletedToday: wordsCompletedToday,
            keystrokesSaved: keystrokesSaved,
            suggestionsShown: suggestionsShown
        )
    }

    func recordAcceptedWord(_ word: String) {
        rolloverIfNeeded()
        wordsCompletedToday += 1
        keystrokesSaved += max(1, word.count) + 1  // word + trailing space
        history[Self.dayKey(.now)] = wordsCompletedToday
        persist()
    }

    /// Returns word counts for the last `days` days (oldest first). Missing days
    /// are reported as 0.
    func dailyHistory(days: Int = 7) -> [(date: Date, words: Int)] {
        rolloverIfNeeded()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [(Date, Int)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = Self.dayKey(d)
            out.append((d, history[key] ?? 0))
        }
        return out
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    func recordShownSuggestion() {
        rolloverIfNeeded()
        suggestionsShown += 1
        persist()
    }

    func resetStatistics() {
        wordsCompletedToday = 0
        keystrokesSaved = 0
        suggestionsShown = 0
        persist()
    }

    private func rolloverIfNeeded() {
        let day = currentDayOrdinal()
        if day != lastResetDay {
            wordsCompletedToday = 0
            lastResetDay = day
            persist()
        }
    }

    private func currentDayOrdinal() -> Int {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    private func persist() {
        let d = QalamDefaults.suite
        d.set(wordsCompletedToday, forKey: Keys.wordsCompletedToday)
        d.set(keystrokesSaved,     forKey: Keys.keystrokesSaved)
        d.set(suggestionsShown,    forKey: Keys.suggestionsShown)
        d.set(lastResetDay,        forKey: Keys.lastResetDay)
        // Trim history to last ~30 days to bound size.
        if history.count > 60 {
            let cal = Calendar.current
            let cutoff = cal.date(byAdding: .day, value: -30, to: Date()) ?? .now
            let cutoffKey = Self.dayKey(cutoff)
            history = history.filter { $0.key >= cutoffKey }
        }
        d.set(history, forKey: Keys.history)
    }
}
