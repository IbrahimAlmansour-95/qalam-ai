import Foundation
import CryptoKit
import CommonCrypto

/// What can go wrong with a sync file. Kept separate from the transport so
/// the UI can say something useful ("wrong passphrase") instead of "error".
enum SyncErrorKind: Equatable, Sendable {
    /// The file is a QalamAI sync file, but this passphrase can't open it.
    /// Also covers a tampered header — authentication can't tell them apart.
    case wrongPassphrase
    /// The passphrase couldn't be stored or read back.
    case keychainUnavailable
    /// Reading or writing iCloud Drive failed.
    case io
    /// Not a QalamAI sync file, or written by a newer format.
    case badFormat
}

enum SyncError: Error, Sendable {
    case wrongPassphrase
    case badFormat
    case keyDerivation
}

/// Cleartext prologue of a sync file: enough to derive the key again, and
/// nothing about its contents. It is authenticated (passed to AES-GCM as
/// additional data), so editing it makes the file fail to open.
struct SyncHeader: Codable, Sendable, Equatable {
    let v: Int
    let kdf: String        // "pbkdf2-sha256"
    let iter: Int          // PBKDF2 rounds
    let salt: String       // base64, 16 random bytes
}

/// File format and crypto for the iCloud Drive copy. Nonisolated on purpose:
/// key derivation takes a few hundred milliseconds, so it is only ever called
/// from `SyncFileIO` (off the main thread).
///
/// Layout: `"QSYNC1\n"` + header JSON + `"\n"` + AES-GCM combined box.
enum SyncCrypto {
    static let magic = Data("QSYNC1\n".utf8)
    static let version = 1
    static let kdfName = "pbkdf2-sha256"
    /// Well above the 210 000 OWASP floor for PBKDF2-SHA256 and still ~0.2 s
    /// on Apple silicon. Old files keep opening with the rounds in their own
    /// header.
    static let iterations = 310_000
    static let minIterations = 100_000
    static let maxIterations = 5_000_000
    static let saltBytes = 16
    static let keyBytes = 32

    static func newHeader() -> SyncHeader {
        var salt = Data(count: saltBytes)
        let ok = salt.withUnsafeMutableBytes { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            return SecRandomCopyBytes(kSecRandomDefault, saltBytes, base) == errSecSuccess
        }
        if !ok {
            // Never ship a predictable salt: fall back to the system RNG.
            salt = Data((0..<saltBytes).map { _ in UInt8.random(in: 0...255) })
        }
        return SyncHeader(v: version, kdf: kdfName, iter: iterations,
                          salt: salt.base64EncodedString())
    }

    /// PBKDF2-SHA256 → 256-bit key. nil when CommonCrypto refuses the input.
    static func deriveKey(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey? {
        guard !salt.isEmpty, iterations > 0, !passphrase.isEmpty else { return nil }
        let pass = Array(passphrase.utf8).map { Int8(bitPattern: $0) }
        var out = [UInt8](repeating: 0, count: keyBytes)
        let status = salt.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return Int32(kCCParamError)
            }
            return CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pass, pass.count,
                base, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &out, out.count)
        }
        guard status == Int32(kCCSuccess) else { return nil }
        return SymmetricKey(data: Data(out))
    }

    static func seal(_ plaintext: Data, header: SyncHeader, key: SymmetricKey) throws -> Data {
        let headerData = try JSONEncoder().encode(header)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: headerData)
        guard let combined = box.combined else { throw SyncError.badFormat }
        var out = magic
        out.append(headerData)
        out.append(0x0A)
        out.append(combined)
        return out
    }

    /// Opens a sync file. `keyCache` keeps derived keys for this passphrase
    /// and salt, so a 310 000-round derivation happens once per file, not
    /// once per sync.
    static func open(_ file: Data, passphrase: String,
                     keyCache: inout [String: SymmetricKey]) throws -> (SyncHeader, Data) {
        guard file.count > magic.count, file.prefix(magic.count) == magic else {
            throw SyncError.badFormat
        }
        let rest = file.dropFirst(magic.count)
        guard let newline = rest.firstIndex(of: 0x0A) else { throw SyncError.badFormat }
        let headerData = Data(rest[rest.startIndex..<newline])
        let body = Data(rest[rest.index(after: newline)...])
        guard let header = try? JSONDecoder().decode(SyncHeader.self, from: headerData),
              header.v == version, header.kdf == kdfName,
              header.iter >= minIterations, header.iter <= maxIterations,
              let salt = Data(base64Encoded: header.salt), salt.count >= 8,
              !body.isEmpty
        else { throw SyncError.badFormat }

        let key = try derivedKey(for: header, salt: salt, passphrase: passphrase, cache: &keyCache)
        guard let box = try? AES.GCM.SealedBox(combined: body) else { throw SyncError.badFormat }
        guard let plain = try? AES.GCM.open(box, using: key, authenticating: headerData) else {
            // Wrong passphrase, or someone edited the file. Indistinguishable
            // by design — both mean "don't touch this remote copy".
            throw SyncError.wrongPassphrase
        }
        return (header, plain)
    }

    private static func derivedKey(for header: SyncHeader, salt: Data, passphrase: String,
                                   cache: inout [String: SymmetricKey]) throws -> SymmetricKey {
        let id = cacheID(salt: salt, iterations: header.iter, passphrase: passphrase)
        if let cached = cache[id] { return cached }
        guard let key = deriveKey(passphrase: passphrase, salt: salt, iterations: header.iter) else {
            throw SyncError.keyDerivation
        }
        if cache.count > 8 { cache.removeAll() }
        cache[id] = key
        return key
    }

    /// A stable id for (passphrase, salt, rounds) that never stores the
    /// passphrase itself — a hash of all three.
    private static func cacheID(salt: Data, iterations: Int, passphrase: String) -> String {
        var input = Data("qalam-sync-key-cache/\(iterations)/".utf8)
        input.append(salt)
        input.append(Data(passphrase.utf8))
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}
