import Foundation
import os

/// App-wide logging. Every message goes to the unified log (Console.app,
/// subsystem `com.qalamai.app`); `info` and above are also appended to a small
/// rotating file at ~/Library/Logs/QalamAI/qalamai.log (1 MB × 3 files) so
/// "Copy diagnostics" can include a recent tail.
///
/// PRIVACY CONTRACT — messages are emitted `.public` and written to disk, so
/// they may contain ONLY static text plus non-user values: counts, durations,
/// status codes, pids, bundle ids, model tags, error domains/codes. Never
/// typed text, clipboard, OCR text, prompts, suggestions, web hosts or URLs,
/// window titles, AX values, custom instructions, snippets, My Info, or raw
/// Ollama stderr/stdout (the engine can echo request data).
///
/// Nonisolated and thread-safe: callable from actors, termination handlers
/// and the keystroke tap. File IO runs on a private serial queue.
enum QLog {
    enum Category: String, CaseIterable, Sendable {
        case app, engine, ax, input, suggestion, overlay, profiles, personalization, sync, diagnostics
    }

    static let subsystem = "com.qalamai.app"
    /// Longer messages are cut (a log line is never a document).
    static let maxMessageLength = 500

    /// Unified log only — never written to the file.
    static func debug(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.debug, category, message())
    }

    static func info(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.info, category, message())
    }

    static func notice(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.notice, category, message())
    }

    static func error(_ category: Category, _ message: @autoclosure () -> String) {
        emit(.error, category, message())
    }

    /// `~/Library/Logs/QalamAI` — also holds `diagnostics/` (MetricKit).
    static var logDirectory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return library.appendingPathComponent("Logs/\(Constants.appName)", isDirectory: true)
    }

    /// The last `n` lines of the file log (oldest first), spanning the
    /// previous rotation when the current file is short.
    static func recentFileLines(_ n: Int) -> [String] {
        fileSink.tail(n)
    }

    /// Blocks until queued file writes are done (e.g. right before `exit`).
    static func flush() {
        fileSink.flush()
    }

    /// Stops file logging for the rest of this process — the uninstaller calls
    /// it before trashing the log folder so a late line can't re-create it.
    static func disableFileLogging() {
        fileSink.disable()
    }

    // MARK: - Internals

    fileprivate enum Level: String {
        case debug = "DEBUG", info = "INFO", notice = "NOTICE", error = "ERROR"
    }

    private static let loggers: [Category: Logger] = Dictionary(
        uniqueKeysWithValues: Category.allCases.map { ($0, Logger(subsystem: subsystem, category: $0.rawValue)) })

    private static let fileSink = QLogFileSink(directory: logDirectory)

    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)

    private static func emit(_ level: Level, _ category: Category, _ raw: String) {
        // One entry per line; bounded length.
        var message = raw.replacingOccurrences(of: "\n", with: " ")
        if message.count > maxMessageLength {
            message = String(message.prefix(maxMessageLength)) + "…"
        }
        let logger = loggers[category] ?? Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
            return
        case .info:   logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .error:  logger.error("\(message, privacy: .public)")
        }
        let stamp = Date().formatted(timestampStyle)
        fileSink.append("\(stamp) \(level.rawValue) [\(category.rawValue)] \(message)\n")
    }
}

/// Size-capped rotating file behind `QLog`: `qalamai.log` → `qalamai.1.log`
/// → `qalamai.2.log` (oldest dropped). All state lives on `queue`.
private final class QLogFileSink: @unchecked Sendable {
    private static let maxBytes: UInt64 = 1_000_000

    private let queue = DispatchQueue(label: "com.qalamai.log", qos: .utility)
    private let directory: URL
    private let current: URL
    private let rotated1: URL
    private let rotated2: URL
    private var handle: FileHandle?
    private var size: UInt64 = 0
    private var disabled = false

    init(directory: URL) {
        self.directory = directory
        self.current = directory.appendingPathComponent("qalamai.log")
        self.rotated1 = directory.appendingPathComponent("qalamai.1.log")
        self.rotated2 = directory.appendingPathComponent("qalamai.2.log")
    }

    func append(_ line: String) {
        queue.async { self.write(line) }
    }

    func flush() {
        queue.sync {}
    }

    func disable() {
        queue.sync {
            disabled = true
            try? handle?.close()
            handle = nil
        }
    }

    func tail(_ n: Int) -> [String] {
        guard n > 0 else { return [] }
        return queue.sync {
            var lines = Self.lastLines(of: current, maxBytes: 96_000)
            if lines.count < n {
                lines = Self.lastLines(of: rotated1, maxBytes: 96_000) + lines
            }
            return Array(lines.suffix(n))
        }
    }

    // MARK: queue-only

    private func write(_ line: String) {
        guard !disabled else { return }
        let data = Data(line.utf8)
        if handle == nil { open() }
        if handle != nil, size + UInt64(data.count) > Self.maxBytes {
            rotate()
        }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            size += UInt64(data.count)
        } catch {
            // Disk full / folder removed: drop the handle, retry on the next line.
            try? handle.close()
            self.handle = nil
        }
    }

    private func open() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            return
        }
        if !fm.fileExists(atPath: current.path) {
            guard fm.createFile(atPath: current.path, contents: nil,
                                attributes: [.posixPermissions: 0o600]) else { return }
        }
        guard let h = try? FileHandle(forWritingTo: current) else { return }
        size = (try? h.seekToEnd()) ?? 0
        handle = h
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: rotated2)
        try? fm.moveItem(at: rotated1, to: rotated2)
        try? fm.moveItem(at: current, to: rotated1)
        size = 0
        open()
    }

    private static func lastLines(of url: URL, maxBytes: UInt64) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        guard let end = try? h.seekToEnd() else { return [] }
        let start = end > maxBytes ? end - maxBytes : 0
        guard (try? h.seek(toOffset: start)) != nil,
              let data = try? h.readToEnd(), !data.isEmpty else { return [] }
        var lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        // Started mid-file: the first line is partial.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }
}
