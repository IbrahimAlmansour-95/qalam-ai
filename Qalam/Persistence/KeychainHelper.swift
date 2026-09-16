import Foundation
import Security

/// Legacy login-keychain generic passwords (no Data Protection keychain, no
/// access groups, no iCloud synchronization — all of those need an Apple
/// Developer Team ID, which this app doesn't have).
///
/// Every call is synchronous keychain IO, so it belongs OFF the main thread:
/// a login keychain that is locked, or an ACL prompt on a legacy item, can
/// block for as long as the user takes to answer. The one exception is
/// `Uninstaller`, which deletes an item on main right before terminating.
enum KeychainHelper {
    /// Reading has to distinguish "there is no item" from "the keychain
    /// couldn't answer": a caller that treats a transient failure as "no
    /// item" would mint a new key and orphan the data encrypted with the old
    /// one.
    enum ReadResult: Sendable {
        case found(Data)
        case notFound
        case failed(OSStatus)
    }

    static func read(service: String, account: String) -> ReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .failed(errSecInternalError) }
            return .found(data)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed(status)
        }
    }

    /// Updates the existing item, or adds one. Returns false on any failure
    /// (the caller falls back to the 0600 file).
    @discardableResult
    static func write(_ data: Data, service: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update = SecItemUpdate(base as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the item. A missing item counts as success.
    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// A small secret stored as a 0600 file — the fallback for when the keychain
/// refuses to store an item (no Team ID means we can't rely on it being
/// available in every environment).
enum SecretFile {
    static func read(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    /// Writes `data` with 0600 permissions inside a 0700 directory, replacing
    /// any previous file atomically.
    @discardableResult
    static func write(_ data: Data, to url: URL) -> Bool {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        do {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
            }
            // Write beside the target, then replace — never a half-written key.
            let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp")
            if fm.fileExists(atPath: tmp.path) { try? fm.removeItem(at: tmp) }
            guard fm.createFile(atPath: tmp.path, contents: data,
                                attributes: [.posixPermissions: 0o600])
            else { return false }
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
