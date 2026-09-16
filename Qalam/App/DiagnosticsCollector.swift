import Foundation
import MetricKit

/// Local crash / hang diagnostics — nothing ever leaves the Mac.
///
/// * Subscribes to MetricKit and keeps the diagnostic payloads macOS hands us
///   (for earlier sessions, at most about once a day) as JSON under
///   ~/Library/Logs/QalamAI/diagnostics (folder 0700, files 0600, newest 20).
///   Objective-C exception messages and their arguments are stripped before
///   writing: they are the one place a runtime value could appear.
/// * `lastCrashSummary()` reads back only a handful of numeric/metadata keys
///   from those files and from macOS's own crash reports
///   (~/Library/Logs/DiagnosticReports/QalamAI*.ips), for "Copy diagnostics".
///
/// SDK note: `MXMetricManager` / `MXMetricManagerSubscriber` are marked
/// `API_TO_BE_DEPRECATED` (no warning). The newer `MetricManager` Swift API
/// isn't available on the macOS 14 deployment target.
final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = DiagnosticsCollector()

    static let maxStoredPayloads = 20
    private static let payloadSuffix = "-diagnostic.json"

    /// `~/Library/Logs/QalamAI/diagnostics`
    static var directory: URL {
        QLog.logDirectory.appendingPathComponent("diagnostics", isDirectory: true)
    }

    struct CrashSummary: Sendable {
        let date: Date
        let kind: String
        let detail: String
    }

    /// Serializes payload writes (MetricKit calls back on a background queue).
    private let lock = NSLock()
    private var started = false
    private var stopped = false

    private override init() {
        super.init()
    }

    /// Subscribes once. Call from `applicationDidFinishLaunching`.
    func start() {
        lock.lock()
        let first = !started
        started = true
        lock.unlock()
        guard first else { return }

        MXMetricManager.shared.add(self)
        // Payloads delivered while QalamAI wasn't running are still listed
        // here; `store` skips ones already on disk.
        DispatchQueue.global(qos: .utility).async {
            let past = MXMetricManager.shared.pastDiagnosticPayloads
            if !past.isEmpty { self.store(past) }
        }
    }

    /// Unsubscribes and ignores anything still in flight (uninstall: the
    /// folder is about to be trashed and must not be re-created).
    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        store(payloads)
    }

    // MARK: - Writing

    private func store(_ payloads: [MXDiagnosticPayload]) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        let fm = FileManager.default
        let dir = Self.directory
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            QLog.error(.diagnostics, "diagnostics folder unavailable (\((error as NSError).domain) \((error as NSError).code))")
            return
        }

        var written = 0
        for payload in payloads {
            guard let data = Self.sanitizedJSON(payload.jsonRepresentation()) else {
                QLog.error(.diagnostics, "skipped an unreadable diagnostic payload")
                continue
            }
            let base = Self.fileStamp(payload.timeStampEnd)
            // Same payload again (pastDiagnosticPayloads after a relaunch) →
            // identical bytes under the same name → skip. A different payload
            // with the same end time gets a numbered name.
            var index = 1
            var duplicate = false
            var url = dir.appendingPathComponent(base + Self.payloadSuffix)
            while fm.fileExists(atPath: url.path) {
                if fm.contents(atPath: url.path) == data { duplicate = true; break }
                index += 1
                url = dir.appendingPathComponent("\(base)-\(index)\(Self.payloadSuffix)")
            }
            guard !duplicate else { continue }
            if fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) {
                written += 1
            }
        }
        guard written > 0 else { return }
        let crashes = payloads.reduce(0) { $0 + ($1.crashDiagnostics?.count ?? 0) }
        let hangs = payloads.reduce(0) { $0 + ($1.hangDiagnostics?.count ?? 0) }
        QLog.notice(.diagnostics, "stored \(written) diagnostic payload(s): \(crashes) crash, \(hangs) hang")
        pruneStoredPayloads()
    }

    /// Keeps the newest `maxStoredPayloads` files (names sort chronologically).
    private func pruneStoredPayloads() {
        let files = Self.storedPayloadFiles()
        guard files.count > Self.maxStoredPayloads else { return }
        for url in files.dropLast(Self.maxStoredPayloads) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Re-serializes the payload with Objective-C exception messages removed
    /// (`composedMessage` / `arguments` can carry runtime values). Sorted keys
    /// make the bytes stable so re-delivered payloads dedupe.
    private static func sanitizedJSON(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let cleaned = strip(object)
        guard JSONSerialization.isValidJSONObject(cleaned) else { return nil }
        return try? JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .sortedKeys])
    }

    private static let strippedKeys: Set<String> = ["composedMessage", "arguments"]

    private static func strip(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, inner) in dict where !strippedKeys.contains(key) {
                out[key] = strip(inner)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { strip($0) }
        }
        return value
    }

    // MARK: - Reading

    /// Newest crash or hang known locally: our MetricKit payloads, or macOS's
    /// own crash report for QalamAI — whichever is more recent. Only numeric
    /// codes and the app version are read; never thread names, frames or
    /// messages.
    static func lastCrashSummary() -> CrashSummary? {
        [newestPayloadSummary(), newestSystemReportSummary()]
            .compactMap { $0 }
            .max { $0.date < $1.date }
    }

    private static func storedPayloadFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasSuffix(payloadSuffix) }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    private static func newestPayloadSummary() -> CrashSummary? {
        for url in storedPayloadFiles().reversed() {
            guard let data = FileManager.default.contents(atPath: url.path),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            let date = parseFileStamp(url.lastPathComponent) ?? modificationDate(url) ?? .distantPast
            if let crashes = root["crashDiagnostics"] as? [[String: Any]], let first = crashes.first {
                let meta = first["diagnosticMetaData"] as? [String: Any] ?? [:]
                let parts = [("exceptionType", "exceptionType"), ("signal", "signal"),
                             ("exceptionCode", "code"), ("appVersion", "app")]
                    .compactMap { key, label in scalar(meta[key]).map { "\(label)=\($0)" } }
                return CrashSummary(date: date, kind: "crash (MetricKit)",
                                    detail: parts.joined(separator: " "))
            }
            if let hangs = root["hangDiagnostics"] as? [Any], !hangs.isEmpty {
                return CrashSummary(date: date, kind: "hang (MetricKit)", detail: "\(hangs.count) report(s)")
            }
        }
        return nil
    }

    private static func newestSystemReportSummary() -> CrashSummary? {
        let fm = FileManager.default
        guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let dir = library.appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }
        let newest = urls
            .filter { $0.lastPathComponent.hasPrefix(Constants.appName) && $0.pathExtension == "ips" }
            .compactMap { url in modificationDate(url).map { (url, $0) } }
            .max { $0.1 < $1.1 }
        guard let newest, let data = fm.contents(atPath: newest.0.path) else { return nil }
        let date = newest.1

        // .ips = one line of header JSON, then the report body JSON.
        let newline = UInt8(ascii: "\n")
        let headerData = data.prefix { $0 != newline }
        let bodyData = data.dropFirst(headerData.count)
        let header = (try? JSONSerialization.jsonObject(with: Data(headerData))) as? [String: Any] ?? [:]
        let body = (try? JSONSerialization.jsonObject(with: Data(bodyData))) as? [String: Any] ?? [:]

        let bugType = scalar(header["bug_type"]) ?? "?"
        let kind = (bugType == "309" || bugType == "109") ? "crash (macOS report)" : "report \(bugType) (macOS)"
        let exception = body["exception"] as? [String: Any] ?? [:]
        let parts = [scalar(exception["type"]).map { "exception=\($0)" },
                     scalar(exception["signal"]).map { "signal=\($0)" },
                     scalar(header["app_version"]).map { "app=\($0)" }]
            .compactMap { $0 }
        return CrashSummary(date: date, kind: kind, detail: parts.joined(separator: " "))
    }

    /// A short number or identifier-like string; anything else is dropped.
    private static func scalar(_ value: Any?) -> String? {
        if let n = value as? NSNumber { return n.stringValue }
        guard let s = value as? String, !s.isEmpty, s.count <= 32,
              s.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) })
        else { return nil }
        return s
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func stampFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }

    private static func fileStamp(_ date: Date) -> String {
        stampFormatter().string(from: date)
    }

    private static func parseFileStamp(_ name: String) -> Date? {
        stampFormatter().date(from: String(name.prefix(15)))
    }
}
