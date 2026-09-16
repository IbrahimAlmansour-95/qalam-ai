import Foundation
import CryptoKit

/// Every byte that goes to or from iCloud Drive, plus the crypto around it.
///
/// An actor, so reads and writes are serialised and nothing here can run on
/// the main thread. The blocking parts (NSFileCoordinator, key derivation)
/// are pushed onto a private queue and awaited, so the actor itself never
/// blocks either — a file that is still materialising can't stall typing.
actor SyncFileIO {
    static let shared = SyncFileIO()

    /// A dataless file can block for as long as the download takes. We give
    /// up well before the user thinks the app is stuck.
    static let readTimeout: TimeInterval = 30
    static let writeTimeout: TimeInterval = 60
    /// A sync file larger than this is not ours to read into memory.
    static let maxFileBytes = 64 * 1024 * 1024

    enum ReadOutcome: Sendable {
        case missing
        /// The file exists in iCloud but its contents aren't on this Mac yet.
        case notDownloaded
        case payload(SyncPayload)
        case failure(SyncErrorKind)
    }

    /// Derived keys for the passphrases seen this session, so a 310 000-round
    /// derivation happens once per file rather than once per sync.
    private var keyCache: [String: SymmetricKey] = [:]

    private init() {}

    // MARK: - Folder

    /// Creates `<iCloud Drive>/QalamAI` when missing. false = couldn't.
    func ensureFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) { return isDir.boolValue }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            QLog.error(.sync, "could not create the sync folder (\((error as NSError).code))")
            return false
        }
    }

    /// iCloud's own conflict copies: "qalam-sync-v1 2.qsync" and friends.
    func conflictCopies(in folder: URL, baseName: String, fileExtension: String) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])
        else { return [] }
        let canonical = "\(baseName).\(fileExtension)"
        return entries.filter { url in
            let name = url.lastPathComponent
            return name != canonical && name.hasPrefix(baseName)
                && name.hasSuffix(".\(fileExtension)")
        }
    }

    func trash(_ urls: [URL]) {
        let fm = FileManager.default
        for url in urls where fm.fileExists(atPath: url.path) {
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
            } catch {
                QLog.error(.sync, "could not move a sync file to the Trash (\((error as NSError).code))")
            }
        }
    }

    // MARK: - Reading

    func readPayload(at url: URL, passphrase: String) async -> ReadOutcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            // A file that exists only in iCloud can show up as ".name.icloud".
            if let placeholder = placeholderURL(for: url), fm.fileExists(atPath: placeholder.path) {
                requestDownload(url)
                return .notDownloaded
            }
            return .missing
        }
        if !isDownloaded(url) {
            requestDownload(url)
            return .notDownloaded
        }

        let result = await run(timeout: Self.readTimeout) { () -> ReadResult in
            var coordinatorError: NSError?
            var data: Data?
            var failure: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(
                readingItemAt: url, options: [.withoutChanges], error: &coordinatorError
            ) { readURL in
                do {
                    data = try Data(contentsOf: readURL)
                } catch {
                    failure = error as NSError
                }
            }
            let error = coordinatorError ?? failure
            return ReadResult(data: data,
                              errorDomain: error?.domain ?? "",
                              errorCode: error?.code ?? 0)
        }

        guard let result else {
            QLog.notice(.sync, "reading the cloud copy timed out")
            return .notDownloaded
        }
        guard let blob = result.data else {
            // "not downloaded yet" also surfaces as a Cocoa read error.
            if result.errorDomain == NSCocoaErrorDomain,
               result.errorCode == CocoaError.Code.fileReadNoSuchFile.rawValue
                || result.errorCode == CocoaError.Code.ubiquitousFileUnavailable.rawValue
                || result.errorCode == CocoaError.Code.ubiquitousFileNotUploadedDueToQuota.rawValue {
                requestDownload(url)
                return .notDownloaded
            }
            QLog.error(.sync, "cloud copy unreadable (\(result.errorCode))")
            return .failure(.io)
        }
        guard blob.count <= Self.maxFileBytes else { return .failure(.badFormat) }
        return decode(blob, passphrase: passphrase)
    }

    private func decode(_ blob: Data, passphrase: String) -> ReadOutcome {
        do {
            let (_, plain) = try SyncCrypto.open(blob, passphrase: passphrase, keyCache: &keyCache)
            let payload = try JSONDecoder().decode(SyncPayload.self, from: plain)
            guard payload.version <= SyncCrypto.version else { return .failure(.badFormat) }
            return .payload(payload)
        } catch SyncError.wrongPassphrase {
            return .failure(.wrongPassphrase)
        } catch {
            return .failure(.badFormat)
        }
    }

    // MARK: - Writing

    /// Seals and replaces the file atomically. Returns nil on success.
    func writePayload(_ payload: SyncPayload, to url: URL, passphrase: String) async -> SyncErrorKind? {
        let json: Data
        do {
            json = try JSONEncoder().encode(payload)
        } catch {
            return .badFormat
        }
        let header = SyncCrypto.newHeader()
        guard let salt = Data(base64Encoded: header.salt),
              let key = SyncCrypto.deriveKey(passphrase: passphrase, salt: salt,
                                             iterations: header.iter),
              let blob = try? SyncCrypto.seal(json, header: header, key: key)
        else { return .badFormat }

        let outcome = await run(timeout: Self.writeTimeout) { () -> WriteResult in
            var coordinatorError: NSError?
            var writeError: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(
                writingItemAt: url, options: [.forReplacing], error: &coordinatorError
            ) { writeURL in
                let fm = FileManager.default
                let dir = writeURL.deletingLastPathComponent()
                let tmp = dir.appendingPathComponent(".\(writeURL.lastPathComponent).tmp")
                do {
                    if fm.fileExists(atPath: tmp.path) { try? fm.removeItem(at: tmp) }
                    try blob.write(to: tmp, options: [.atomic])
                    if fm.fileExists(atPath: writeURL.path) {
                        _ = try fm.replaceItemAt(writeURL, withItemAt: tmp)
                    } else {
                        try fm.moveItem(at: tmp, to: writeURL)
                    }
                } catch {
                    try? fm.removeItem(at: tmp)
                    writeError = error as NSError
                }
            }
            let error = coordinatorError ?? writeError
            return WriteResult(errorCode: error?.code ?? 0, failed: error != nil)
        }

        guard let outcome else {
            QLog.notice(.sync, "writing the cloud copy timed out")
            return .io
        }
        if outcome.failed {
            QLog.error(.sync, "cloud copy not written (\(outcome.errorCode))")
            return .io
        }
        return nil
    }

    // MARK: - iCloud helpers

    private func isDownloaded(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              let status = values.ubiquitousItemDownloadingStatus
        else { return true }   // not an iCloud item (or unknown): just read it
        return status == .current || status == .downloaded
    }

    /// Asks iCloud to materialise the file. Allowed without any entitlement;
    /// if the call is refused we simply retry on the next cycle.
    private func requestDownload(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    private func placeholderURL(for url: URL) -> URL? {
        let name = url.lastPathComponent
        guard !name.isEmpty else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(".\(name).icloud")
    }

    // MARK: - Bounded blocking work

    private struct ReadResult: Sendable {
        let data: Data?
        let errorDomain: String
        let errorCode: Int
    }

    private struct WriteResult: Sendable {
        let errorCode: Int
        let failed: Bool
    }

    /// Runs `body` on a private queue and waits at most `timeout` seconds.
    /// nil = it is still running (the thread is left to finish on its own —
    /// file coordination can't be cancelled).
    private func run<T: Sendable>(timeout: TimeInterval,
                                  _ body: @escaping @Sendable () -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let box = ResumeOnce<T>(continuation)
            Self.workQueue.async {
                let value = body()
                box.finish(value)
            }
            // A separate queue: the timer must not wait behind the work it
            // is timing.
            Self.timeoutQueue.asyncAfter(deadline: .now() + timeout) {
                box.finish(nil)
            }
        }
    }

    private static let workQueue = DispatchQueue(label: "com.qalamai.app.sync.io", qos: .utility)
    private static let timeoutQueue = DispatchQueue(label: "com.qalamai.app.sync.timeout", qos: .utility)

    /// Resumes a continuation exactly once, whichever path gets there first.
    private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?

        init(_ continuation: CheckedContinuation<T?, Never>) {
            self.continuation = continuation
        }

        func finish(_ value: T?) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }
}
