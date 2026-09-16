import Foundation

// MARK: - Wire format

/// One synced thing. `key` is a natural key (a snippet's trigger, a profile's
/// id) so the same item on two Macs is recognised as the same item even
/// though it was created twice. `payload` is the item's JSON; `nil` with
/// `deleted == true` is a tombstone.
struct SyncItem: Codable, Sendable, Equatable {
    let key: String
    let modifiedAt: Date
    let deviceID: String
    let deleted: Bool
    let payload: Data?
}

/// The decrypted contents of one sync file.
struct SyncPayload: Codable, Sendable {
    let version: Int
    let deviceID: String
    let items: [SyncItem]
}

/// Key builders. Every key starts with its kind, which is also how the merge
/// decides which store an incoming item belongs to.
enum SyncKey {
    static let snippetPrefix = "snippet:"
    static let modePrefix = "mode:"
    static let profilePrefix = "profile:"
    static let myInfoPrefix = "myinfo:"
    static let samplePrefix = "sample:"
    static let customInstructions = "settings:customInstructions"

    static func snippet(_ trigger: String) -> String { snippetPrefix + trigger }
    static func mode(_ id: String) -> String { modePrefix + id }
    static func profile(_ id: String) -> String { profilePrefix + id }
    static func myInfo(_ id: String) -> String { myInfoPrefix + id }
    static func sample(_ id: String) -> String { samplePrefix + id }

    /// Belongs to the settings bundle (everything except writing samples).
    static func isSettings(_ key: String) -> Bool {
        key.hasPrefix(snippetPrefix) || key.hasPrefix(modePrefix)
            || key.hasPrefix(profilePrefix) || key.hasPrefix(myInfoPrefix)
            || key == customInstructions
    }

    static func isSample(_ key: String) -> Bool { key.hasPrefix(samplePrefix) }

    /// The part after the prefix (a trigger, an id, …).
    static func value(_ key: String, prefix: String) -> String {
        String(key.dropFirst(prefix.count))
    }
}

// MARK: - Merge

/// Last edit wins, per item. Pure and nonisolated so it can be reasoned
/// about (and exercised) on its own: no stores, no files, no clock beyond
/// the tombstone cutoff that is passed in.
enum SyncMerge {
    struct Outcome: Sendable {
        /// What the cloud file should contain after this round.
        let merged: [String: SyncItem]
        /// The remote winners this Mac still has to write into its stores.
        let toApply: [SyncItem]
    }

    static func merge(local: [String: SyncItem],
                      remote: [SyncItem],
                      tombstoneCutoff: Date) -> Outcome {
        var merged = local
        var toApply: [SyncItem] = []
        for item in remote {
            guard let mine = merged[item.key] else {
                merged[item.key] = item
                toApply.append(item)
                continue
            }
            if mine == item { continue }
            if wins(item, over: mine) {
                merged[item.key] = item
                toApply.append(item)
            }
        }
        merged = merged.filter { !($0.value.deleted && $0.value.modifiedAt < tombstoneCutoff) }
        return Outcome(merged: merged, toApply: toApply)
    }

    /// Newer wins; same instant, the greater device id wins; same again, a
    /// deletion wins; and finally the bytes decide — anything rather than
    /// two Macs each insisting on their own copy forever.
    static func wins(_ candidate: SyncItem, over current: SyncItem) -> Bool {
        if candidate.modifiedAt != current.modifiedAt {
            return candidate.modifiedAt > current.modifiedAt
        }
        if candidate.deviceID != current.deviceID {
            return candidate.deviceID > current.deviceID
        }
        if candidate.deleted != current.deleted { return candidate.deleted }
        return isGreater(candidate.payload, current.payload)
    }

    /// Latest-wins de-duplication of a decoded file (conflict copies are
    /// merged into the same list, so a key can appear more than once).
    static func dictionary(_ items: [SyncItem]) -> [String: SyncItem] {
        var out: [String: SyncItem] = [:]
        for item in items {
            if let existing = out[item.key], !wins(item, over: existing) { continue }
            out[item.key] = item
        }
        return out
    }

    /// True when `lhs` sorts strictly after `rhs`.
    private static func isGreater(_ lhs: Data?, _ rhs: Data?) -> Bool {
        guard let l = lhs else { return false }
        guard let r = rhs else { return true }
        if l.count != r.count { return l.count > r.count }
        return r.lexicographicallyPrecedes(l)
    }
}
