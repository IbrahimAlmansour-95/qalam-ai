import Foundation
import ApplicationServices

/// Finds which website a focused browser field belongs to, via Accessibility.
///
/// Walks `kAXParentAttribute` from the focused element (≤ 40 levels) up to
/// its `AXWindow`:
///   * passes an `AXWebArea` → the field is page content. The host comes
///     from the OUTERMOST web area's `AXURL` (an editor inside an iframe —
///     Google Docs, embedded composers — still counts as the tab's site).
///   * reaches the window without one → browser chrome (address bar, find
///     bar). Safari exposes the page URL as the window's `AXDocument`.
///   * anything else (AX error, level cap) → unknown. Callers never idle a
///     field on "unknown".
///
/// Browsers only. Cached per focused element for 5 s, and at most one walk
/// per app every 500 ms (web apps that re-mount their inputs get a new
/// element on every keystroke). Hosts are never logged.
@MainActor
final class WebDomainDetector {
    static let shared = WebDomainDetector()

    struct Result: Equatable, Sendable {
        /// Normalized host (`ProfileStore.normalizeHost`), nil if unknown.
        let host: String?
        /// true = inside page content, false = browser chrome, nil = unknown.
        let isInWebArea: Bool?

        static let unknown = Result(host: nil, isInWebArea: nil)
    }

    private static let fieldCacheLifetime: TimeInterval = 5
    private static let minWalkInterval: TimeInterval = 0.5
    private static let maxLevels = 40
    private static let maxCacheEntries = 64

    private var fieldCache: [FieldKey: (result: Result, at: TimeInterval)] = [:]
    private var lastWalk: [pid_t: (result: Result, at: TimeInterval)] = [:]

    private init() {}

    /// `role` is the focused element's role when already known (saves a
    /// call). Runs inside the caller's `AXGuard.measure` block.
    func detect(element: AXUIElement, role: String?, bundleID: String?, key: FieldKey) -> Result {
        guard KnownApps.isBrowser(bundleID) else { return .unknown }
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = fieldCache[key], now - cached.at < Self.fieldCacheLifetime {
            return cached.result
        }
        if let recent = lastWalk[key.pid], now - recent.at < Self.minWalkInterval {
            return recent.result
        }
        let result = walk(from: element, role: role)
        lastWalk[key.pid] = (result, now)
        if fieldCache.count >= Self.maxCacheEntries {
            fieldCache = fieldCache.filter { now - $0.value.at < Self.fieldCacheLifetime }
            if fieldCache.count >= Self.maxCacheEntries { fieldCache.removeAll() }
        }
        fieldCache[key] = (result, now)
        return result
    }

    private func walk(from element: AXUIElement, role initialRole: String?) -> Result {
        var current = element
        var webAreas: [AXUIElement] = []
        var window: AXUIElement?
        for level in 0..<Self.maxLevels {
            let role = (level == 0 ? initialRole : nil) ?? stringAttribute(current, kAXRoleAttribute)
            if role == "AXWebArea" {
                webAreas.append(current)
            } else if role == "AXWindow" {
                window = current
                break
            }
            guard let parent = elementAttribute(current, kAXParentAttribute) else { break }
            current = parent
        }

        let isInWebArea: Bool?
        if !webAreas.isEmpty {
            isInWebArea = true
        } else if window != nil {
            isInWebArea = false
        } else {
            isInWebArea = nil
        }

        var host: String?
        for area in webAreas.reversed() {
            if let h = hostAttribute(area, "AXURL") {
                host = h
                break
            }
        }
        if host == nil, let window {
            host = hostAttribute(window, "AXDocument")
        }
        return Result(host: host, isInWebArea: isInWebArea)
    }

    // MARK: - AX helpers (type-checked, no force casts)

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let value = ref,
              CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    /// http(s) host of a URL-valued attribute (CFURL or String).
    private func hostAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let value = ref
        else { return nil }
        let url: URL?
        if CFGetTypeID(value as CFTypeRef) == CFURLGetTypeID() {
            url = unsafeDowncast(value, to: NSURL.self) as URL
        } else if let string = value as? String {
            url = URL(string: string)
        } else {
            url = nil
        }
        guard let url,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = url.host
        else { return nil }
        return ProfileStore.normalizeHost(rawHost)
    }
}
