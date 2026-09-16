import Foundation
import CryptoKit

/// One recorded piece of the user's own writing. Stored encrypted; the text
/// never leaves this Mac and is never logged.
struct WritingSample: Codable, Sendable, Identifiable {
    let id: String
    let text: String
    let bundleID: String
    let domain: String?      // website host, when it was typed in a browser
    let date: Date
    let script: String       // "arabic" | "latin" | "unknown"
}

/// Counts-only mirror of the store, readable without awaiting the actor
/// (Diagnostics runs synchronously on the main actor). Holds no sample text.
final class PersonalizationSnapshot: @unchecked Sendable {
    static let shared = PersonalizationSnapshot()

    private let lock = NSLock()
    private var _sampleCount = 0
    private var _isLoaded = false
    private var _isUnavailable = false

    private init() {}

    var sampleCount: Int { lock.withLock { _sampleCount } }
    var isLoaded: Bool { lock.withLock { _isLoaded } }
    /// True when the key couldn't be read this session — nothing is recorded
    /// or retrieved until it can be (checked again after a minute).
    var isUnavailable: Bool { lock.withLock { _isUnavailable } }

    fileprivate func update(count: Int, loaded: Bool, unavailable: Bool) {
        lock.withLock {
            _sampleCount = count
            _isLoaded = loaded
            _isUnavailable = unavailable
        }
    }
}

/// The encrypted local store of the user's writing samples, plus the
/// retrieval that turns them into a few short style hints for the prompt.
///
/// Everything (file IO, crypto, keychain) happens inside this actor, i.e.
/// never on the main thread. On disk:
/// `~/Library/Application Support/QalamAI/Personalization/` (0700)
///   • `samples.qenc`  — "QPERS1" + AES-GCM sealed JSON
///   • `.store.key`    — 0600 fallback, only when the keychain refuses
actor PersonalizationStore {
    static let shared = PersonalizationStore()

    static let keychainService = "com.qalamai.app.personalization"
    static let keychainAccount = "store-key-v1"

    /// Caps. The oldest samples are dropped first.
    static let maxSamples = 2_000
    static let maxBytes = 5 * 1024 * 1024
    /// Per-sample bookkeeping (id, bundle id, dates) counted against the cap.
    private static let perSampleOverhead = 160

    private static let magic = Data("QPERS1".utf8)
    private static let saveDebounceNs: UInt64 = 3_000_000_000
    /// How long a store whose key couldn't be read stays unavailable.
    private static let retryAfter: TimeInterval = 60

    private var samples: [WritingSample] = []
    private var key: SymmetricKey?
    private var loaded = false
    private var unavailableSince: Date?
    private var saveTask: Task<Void, Never>?
    /// Frequent phrases per script. Rebuilding scans thousands of words, so
    /// it happens lazily and only after the store has moved on a little —
    /// slightly stale phrases are fine, a rebuild per accepted sample is not.
    private var phraseCache: [String: [String]] = [:]
    private var phraseCacheCount = 0
    /// Keywords per sample id, so scoring doesn't re-tokenize the pool on
    /// every request. Dropped whenever samples change.
    private var keywordCache: [String: Set<String>] = [:]

    private init() {}

    // MARK: - Paths

    static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Constants.appSupportDirName, isDirectory: true)
            .appendingPathComponent("Personalization", isDirectory: true)
    }

    private static var samplesURL: URL? {
        directory?.appendingPathComponent("samples.qenc")
    }

    private static var corruptURL: URL? {
        directory?.appendingPathComponent("samples.corrupt.qenc")
    }

    private static var keyFileURL: URL? {
        directory?.appendingPathComponent(".store.key")
    }

    // MARK: - Loading

    /// Reads the key and decrypts the store. Called at launch (only when
    /// personalization is in use) and whenever the feature is switched on —
    /// never from the per-keystroke path, so a keychain prompt can't appear
    /// mid-typing.
    func loadIfNeeded() {
        guard !loaded else { return }
        if let since = unavailableSince, Date().timeIntervalSince(since) < Self.retryAfter { return }
        unavailableSince = nil

        guard let samplesURL = Self.samplesURL, let keyURL = Self.keyFileURL else {
            markUnavailable()
            return
        }
        let samplesExist = FileManager.default.fileExists(atPath: samplesURL.path)
        guard let key = resolveKey(keyURL: keyURL, samplesExist: samplesExist) else {
            // No key AND samples on disk: do nothing at all this session —
            // no new key, no file moved aside, no write. A locked keychain
            // right after login must not throw the user's samples away.
            markUnavailable()
            return
        }
        self.key = key
        if samplesExist { decodeSamples(at: samplesURL, key: key) }
        loaded = true
        publishSnapshot()
        QLog.info(.personalization, "store loaded (\(samples.count) samples)")
    }

    private func markUnavailable() {
        unavailableSince = Date()
        PersonalizationSnapshot.shared.update(count: 0, loaded: false, unavailable: true)
    }

    private func publishSnapshot() {
        PersonalizationSnapshot.shared.update(count: samples.count,
                                              loaded: loaded,
                                              unavailable: false)
    }

    /// The 256-bit store key: keychain → 0600 fallback file → (only when
    /// there is nothing to lose) a fresh one. nil means "can't be obtained
    /// right now and samples exist".
    private func resolveKey(keyURL: URL, samplesExist: Bool) -> SymmetricKey? {
        switch KeychainHelper.read(service: Self.keychainService, account: Self.keychainAccount) {
        case .found(let data) where data.count == 32:
            return SymmetricKey(data: data)
        case .found:
            QLog.error(.personalization, "keychain key has an unexpected size")
            if let data = SecretFile.read(keyURL), data.count == 32 { return SymmetricKey(data: data) }
            return samplesExist ? nil : generateKey(at: keyURL)
        case .notFound:
            if let data = SecretFile.read(keyURL), data.count == 32 { return SymmetricKey(data: data) }
            if samplesExist {
                // The item was removed while its data is still here. Deleting
                // all samples in Settings starts a clean store.
                QLog.error(.personalization, "no key for an existing sample store")
                return nil
            }
            return generateKey(at: keyURL)
        case .failed(let status):
            if let data = SecretFile.read(keyURL), data.count == 32 { return SymmetricKey(data: data) }
            QLog.error(.personalization, "keychain read failed (OSStatus \(status))")
            return samplesExist ? nil : generateKey(at: keyURL)
        }
    }

    private func generateKey(at keyURL: URL) -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        if !KeychainHelper.write(data, service: Self.keychainService, account: Self.keychainAccount) {
            QLog.notice(.personalization, "keychain unavailable — key kept in a 0600 file")
            _ = SecretFile.write(data, to: keyURL)
        }
        return key
    }

    private func decodeSamples(at url: URL, key: SymmetricKey) {
        guard let blob = try? Data(contentsOf: url) else {
            QLog.error(.personalization, "sample store unreadable (file error)")
            return
        }
        guard blob.count > Self.magic.count, blob.prefix(Self.magic.count) == Self.magic else {
            moveAside(url)
            return
        }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(blob.dropFirst(Self.magic.count)))
            let json = try AES.GCM.open(box, using: key)
            samples = try JSONDecoder().decode(StoreFile.self, from: json).samples
        } catch {
            // Authentication failure / unreadable JSON with a key we really
            // did read: keep the file for support, start empty.
            QLog.error(.personalization, "sample store could not be decrypted — starting empty")
            moveAside(url)
            samples = []
        }
    }

    /// Keeps at most one unreadable copy next to the store.
    private func moveAside(_ url: URL) {
        guard let corrupt = Self.corruptURL else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: corrupt.path) { try? fm.removeItem(at: corrupt) }
        try? fm.moveItem(at: url, to: corrupt)
    }

    private struct StoreFile: Codable, Sendable {
        let version: Int
        let samples: [WritingSample]
    }

    // MARK: - Mutation

    func add(_ sample: WritingSample) {
        loadIfNeeded()
        guard loaded, key != nil else { return }
        samples.append(sample)
        prune()
        keywordCache.removeAll()
        publishSnapshot()
        scheduleSave()
        // No sync push here: samples ride the regular cycle (see SyncHooks).
    }

    func counts() -> [String: Int] {
        var out: [String: Int] = [:]
        for s in samples { out[s.bundleID, default: 0] += 1 }
        return out
    }

    /// Whether anything is stored — including a store this session never
    /// opened. Lets Settings offer "delete everything" without a keychain
    /// read (opening the tab must not create a key).
    func hasStoredData() -> Bool {
        if !samples.isEmpty { return true }
        guard let url = Self.samplesURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func delete(bundleID: String) {
        let before = samples.count
        let removed = samples.filter { $0.bundleID == bundleID }.map(\.id)
        samples.removeAll { $0.bundleID == bundleID }
        guard samples.count != before else { return }
        invalidateCaches()
        publishSnapshot()
        saveNow()
        Task { @MainActor in SyncHooks.samplesDeleted(removed) }
    }

    /// User-requested deletion of everything recorded (the key is kept, so a
    /// later sample is encrypted with the same one).
    func deleteAll() {
        saveTask?.cancel()
        saveTask = nil
        let removed = samples.map(\.id)
        samples = []
        Task { @MainActor in SyncHooks.samplesDeleted(removed) }
        invalidateCaches()
        if let url = Self.samplesURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let corrupt = Self.corruptURL {
            try? FileManager.default.removeItem(at: corrupt)
        }
        // A store that was unavailable because its key was gone can start
        // over now that the unreadable file is gone.
        if key == nil {
            loaded = false
            unavailableSince = nil
        }
        PersonalizationSnapshot.shared.update(count: 0, loaded: loaded, unavailable: false)
        QLog.notice(.personalization, "all samples deleted")
    }

    // MARK: - Sync (opt-in, second switch)

    /// The samples as they would go into the encrypted iCloud copy, or nil
    /// when the store isn't open (a locked keychain, or nothing recorded
    /// yet) — in which case sync skips this file entirely rather than
    /// pushing an empty one over a full one.
    func syncSnapshot() -> [WritingSample]? {
        guard loaded, key != nil else { return nil }
        return samples
    }

    /// Writes samples that came from another Mac. Samples never change once
    /// written, so an id we already hold is skipped; one older than
    /// everything we kept is skipped too, otherwise a full store would keep
    /// re-adding and re-pruning the same sample on every sync.
    func applySyncSamples(_ upserts: [WritingSample], deletions: [String]) {
        guard loaded, key != nil else { return }
        var changed = false
        if !deletions.isEmpty {
            let drop = Set(deletions)
            let before = samples.count
            samples.removeAll { drop.contains($0.id) }
            changed = samples.count != before
        }
        let atCapacity = samples.count >= Self.maxSamples
        let oldest = samples.map(\.date).min() ?? .distantPast
        var known = Set(samples.map(\.id))
        for sample in upserts {
            guard !known.contains(sample.id) else { continue }
            if atCapacity && sample.date < oldest { continue }
            samples.append(sample)
            known.insert(sample.id)
            changed = true
        }
        guard changed else { return }
        samples.sort { $0.date < $1.date }
        prune()
        invalidateCaches()
        publishSnapshot()
        saveNow()
    }

    private func invalidateCaches() {
        phraseCache.removeAll()
        phraseCacheCount = 0
        keywordCache.removeAll()
    }

    private func prune() {
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
        var bytes = samples.reduce(0) { $0 + $1.text.utf8.count + Self.perSampleOverhead }
        while bytes > Self.maxBytes, samples.count > 1 {
            bytes -= samples[0].text.utf8.count + Self.perSampleOverhead
            samples.removeFirst()
        }
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.saveDebounceNs)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask = nil
        guard let key, let dir = Self.directory, let url = Self.samplesURL else { return }
        do {
            let json = try JSONEncoder().encode(StoreFile(version: 1, samples: samples))
            let fm = FileManager.default
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
            }
            guard let combined = try AES.GCM.seal(json, using: key).combined else { return }
            var blob = Self.magic
            blob.append(combined)
            try blob.write(to: url, options: [.atomic])
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            QLog.error(.personalization, "could not write the sample store")
        }
    }

    // MARK: - Retrieval

    /// A few short style hints for the prompt, or nil when nothing is
    /// relevant. Pure in-memory work — no IO, no keychain.
    func promptContext(currentText: String,
                       bundleID: String?,
                       host: String?,
                       strength: PersonalizationStrength) -> String? {
        guard strength != .off, loaded, !samples.isEmpty else { return nil }
        let budget = Budget(strength)
        let window = String(currentText.suffix(200))
        let script = Self.scriptName(for: window)
        let keys = Self.keywords(in: window)

        let pool = samples.suffix(Self.retrievalPool)
        let candidates = script == "unknown" ? Array(pool) : pool.filter { $0.script == script }
        guard !candidates.isEmpty else { return nil }

        let now = Date()
        var scored: [(sample: WritingSample, score: Double, overlap: Int)] = []
        scored.reserveCapacity(candidates.count)
        for sample in candidates {
            let overlap = keywords(of: sample).intersection(keys).count
            let sameHost = host != nil && sample.domain == host
            let sameApp = bundleID != nil && sample.bundleID == bundleID
            guard overlap > 0 || sameHost || sameApp else { continue }
            var score = 2 * Double(overlap)
            if sameHost { score += 2 }
            if sameApp { score += 1.5 }
            let ageDays = now.timeIntervalSince(sample.date) / 86_400
            score += max(0, 1 - ageDays / 30)
            scored.append((sample, score, overlap))
        }
        guard !scored.isEmpty else { return nil }
        scored.sort { $0.score > $1.score }

        var excerpts: [String] = []
        var used = 0
        for item in scored.prefix(budget.excerpts * 3) {
            guard excerpts.count < budget.excerpts, used < budget.chars else { break }
            let room = min(Self.maxExcerptChars, budget.chars - used)
            guard room >= 40 else { break }
            let excerpt = Self.excerpt(from: item.sample.text, keywords: keys, maxChars: room)
            guard excerpt.count >= 20, !excerpts.contains(excerpt) else { continue }
            excerpts.append(excerpt)
            used += excerpt.count
        }

        let phrases = frequentPhrases(script: script, limit: budget.phrases)
        guard !excerpts.isEmpty || !phrases.isEmpty else { return nil }

        var out = "How the user writes (style only, do not copy):"
        for excerpt in excerpts { out += "\n- \(excerpt)" }
        if !phrases.isEmpty {
            out += "\nFrequent phrases: \(phrases.joined(separator: "; "))"
        }
        return out
    }

    /// Only the most recent samples take part in retrieval — enough for a
    /// style signal, cheap enough to stay well under a millisecond.
    private static let retrievalPool = 400
    private static let maxExcerptChars = 160
    /// Samples scanned when the n-gram cache is rebuilt.
    private static let phrasePool = 300
    private static let phraseWordBudget = 40_000
    /// How far the sample count may drift before the phrases are rebuilt.
    private static let phraseRebuildDelta = 10

    private struct Budget {
        let excerpts: Int
        let chars: Int
        let phrases: Int

        init(_ strength: PersonalizationStrength) {
            switch strength {
            case .off, .low: (excerpts, chars, phrases) = (1, 150, 3)
            case .medium:    (excerpts, chars, phrases) = (2, 300, 5)
            case .strong:    (excerpts, chars, phrases) = (4, 600, 8)
            }
        }
    }

    /// The sentence of `text` with the most keyword overlap, trimmed to
    /// `maxChars` at a word boundary.
    private static func excerpt(from text: String, keywords: Set<String>, maxChars: Int) -> String {
        let sentences = text
            .split(whereSeparator: { ".!?؟\n\r".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 }
        var best = sentences.first ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        var bestOverlap = -1
        for sentence in sentences {
            let overlap = self.keywords(in: sentence).intersection(keywords).count
            if overlap > bestOverlap {
                bestOverlap = overlap
                best = sentence
            }
        }
        if best.count > maxChars {
            var cut = String(best.prefix(maxChars))
            if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > maxChars / 2 {
                cut = String(cut[..<space])
            }
            best = cut
        }
        return best.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A sample's keywords, tokenized once and kept while the store is
    /// unchanged (scoring runs on every suggestion request).
    private func keywords(of sample: WritingSample) -> Set<String> {
        if let cached = keywordCache[sample.id] { return cached }
        let words = Self.keywords(in: sample.text.prefix(600))
        if keywordCache.count > Self.retrievalPool { keywordCache.removeAll() }
        keywordCache[sample.id] = words
        return words
    }

    /// 2–3 word sequences the user repeats (≥ 3 times) in this script.
    /// Rebuilt only once the sample count has moved by `phraseRebuildDelta`,
    /// so a newly recorded sample doesn't make the next suggestion pay for a
    /// full rescan.
    private func frequentPhrases(script: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        if abs(samples.count - phraseCacheCount) >= Self.phraseRebuildDelta {
            phraseCache.removeAll()
        }
        if let cached = phraseCache[script] { return Array(cached.prefix(limit)) }
        var counts: [String: Int] = [:]
        var scanned = 0
        for sample in samples.suffix(Self.phrasePool) where script == "unknown" || sample.script == script {
            let words = sample.text
                .split(whereSeparator: { $0.isWhitespace })
                .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
                .filter { !$0.isEmpty }
            guard words.count >= 2 else { continue }
            scanned += words.count
            for n in 2...3 where words.count >= n {
                for i in 0...(words.count - n) {
                    let phrase = words[i..<(i + n)].joined(separator: " ")
                    if phrase.count >= 6 { counts[phrase, default: 0] += 1 }
                }
            }
            if scanned > Self.phraseWordBudget { break }
        }
        let ranked = counts
            .filter { $0.value >= 3 }
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                if a.key.count != b.key.count { return a.key.count > b.key.count }
                return a.key < b.key
            }
            .map(\.key)
        // Drop a phrase that is already part of a stronger one.
        var kept: [String] = []
        for phrase in ranked {
            if kept.contains(where: { $0.contains(phrase) }) { continue }
            kept.append(phrase)
            if kept.count >= 16 { break }
        }
        phraseCache[script] = kept
        phraseCacheCount = samples.count
        return Array(kept.prefix(limit))
    }

    // MARK: - Text helpers

    static func scriptName(for text: some StringProtocol) -> String {
        switch Script.dominant(in: text) {
        case .arabic:  return "arabic"
        case .latin:   return "latin"
        case .unknown: return "unknown"
        }
    }

    /// Lowercased letter tokens of 3+ characters, minus a small stop list.
    static func keywords(in text: some StringProtocol) -> Set<String> {
        var out: Set<String> = []
        for token in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            guard token.count >= 3 else { continue }
            let word = String(token)
            if stopwords.contains(word) { continue }
            out.insert(word)
        }
        return out
    }

    private static let stopwords: Set<String> = [
        // English
        "the", "and", "for", "that", "with", "you", "this", "are", "was", "but",
        "not", "have", "has", "had", "from", "they", "your", "our", "its", "will",
        "would", "can", "could", "should", "there", "their", "them", "what", "when",
        "which", "who", "how", "all", "any", "been", "just", "like", "get", "got",
        "about", "into", "than", "then", "some", "more", "also", "here",
        // Arabic
        "من", "في", "على", "إلى", "عن", "هذا", "هذه", "ذلك", "التي", "الذي",
        "كان", "كانت", "مع", "أن", "إن", "كما", "لكن", "قد", "هو", "هي",
        "بعد", "قبل", "عند", "كل", "أو", "ثم", "لم", "لا", "ما", "هناك",
    ]
}
