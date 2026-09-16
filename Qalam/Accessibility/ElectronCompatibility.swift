import Foundation
import AppKit
import ApplicationServices

/// Electron apps (Slack, Discord, Notion, VS Code …) ship a full accessibility
/// tree but keep it switched off until an assistive client asks for it, so the
/// focused element has no readable text and QalamAI can't suggest anything.
///
/// The documented switch is the `AXManualAccessibility` attribute on the app's
/// AXApplication element. We never set AppKit's enhanced-user-interface
/// attribute — the other flag often suggested for this — because it is the
/// screen-reader switch and breaks window managers and window animations.
///
/// Applied when: the user turned "Improve compatibility" on for the app, or —
/// once per process — after a failed text read in an app that looks like
/// Electron. VS Code-family editors are never auto-switched: with
/// `editor.accessibilitySupport: auto` they turn into "screen reader
/// optimized" mode, which changes the user's editor without them asking.
/// The flag lives in the target process, so it has to be set again after that
/// app relaunches (a new pid).
@MainActor
final class ElectronCompatibility {
    static let shared = ElectronCompatibility()

    /// Identity of one running app — plain values, safe to carry out of a
    /// notification callback.
    struct AppRef: Sendable, Equatable {
        let pid: pid_t
        let bundleID: String?
        let bundlePath: String?
        let name: String?
    }

    /// Electron-ness per bundle path (a filesystem check, done once).
    private var electronByPath: [String: Bool] = [:]
    /// Processes the flag was successfully set on.
    private var appliedPIDs: Set<pid_t> = []
    /// Processes an automatic attempt was already made for.
    private var attemptedPIDs: Set<pid_t> = []
    /// Last automatic evaluation per pid (rate limit — `noteEmptyRead` runs on
    /// the per-keystroke path).
    private var lastEmptyReadAt: [pid_t: TimeInterval] = [:]
    private var observers: [NSObjectProtocol] = []

    /// Apps the flag was applied to AUTOMATICALLY, so the next launch of one
    /// gets it before its first failed read. Deliberately not the app's
    /// profile: writing `improveCompatibility` there stamps `modifiedAt`,
    /// which makes the app show up as Configured/"Customized" in the Apps
    /// tab, exempts it from `pruneUnconfiguredApps` and pushes it to the
    /// user's other Macs — none of which the user asked for by merely
    /// clicking around in Slack. Lives in the same preferences plist as every
    /// other setting, so it is no new data location for the uninstaller and
    /// nothing new is synced.
    private lazy var autoAppliedBundleIDs: Set<String> =
        Set((QalamDefaults.suite.array(forKey: Self.autoAppliedKey) as? [String]) ?? [])

    private static let autoAppliedKey = "qalam.electronAutoCompatBundleIDs"
    private static let emptyReadInterval: TimeInterval = 2
    private static let frameworkSuffix = "Contents/Frameworks/Electron Framework.framework"
    private static let attribute = "AXManualAccessibility" as CFString

    private init() {}

    // MARK: - Lifecycle

    /// Follows app activation / launch so an app the user enabled gets the
    /// flag again after it relaunches. Call after `ProfileStore.shared.start()`.
    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let ref = ElectronCompatibility.ref(from: note)
                MainActor.assumeIsolated {
                    ElectronCompatibility.shared.appAppeared(ref)
                }
            })
        }
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let ref = ElectronCompatibility.ref(from: note)
            MainActor.assumeIsolated {
                ElectronCompatibility.shared.appTerminated(ref?.pid)
            }
        })
    }

    // MARK: - Detection

    func isElectron(_ app: NSRunningApplication) -> Bool {
        isElectron(Self.ref(for: app))
    }

    /// For the Apps tab: works for apps that aren't running (LaunchServices).
    func isElectron(bundleID: String) -> Bool {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return isElectron(running)
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        return isElectron(path: url.path)
    }

    private func isElectron(_ ref: AppRef?) -> Bool {
        guard let path = ref?.bundlePath else { return false }
        return isElectron(path: path)
    }

    private func isElectron(path: String) -> Bool {
        if let cached = electronByPath[path] { return cached }
        let framework = (path as NSString).appendingPathComponent(Self.frameworkSuffix)
        let exists = FileManager.default.fileExists(atPath: framework)
        electronByPath[path] = exists
        return exists
    }

    // MARK: - Applying

    /// Sets `AXManualAccessibility` on the app's AXApplication element.
    @discardableResult
    func apply(to app: NSRunningApplication) -> Bool {
        apply(to: Self.ref(for: app))
    }

    @discardableResult
    func apply(to ref: AppRef?) -> Bool {
        guard let ref, ref.pid > 0 else { return false }
        let element = AXUIElementCreateApplication(ref.pid)
        AXGuard.configure(element)
        // CFBoolean via NSNumber: `kCFBooleanTrue` is a global the strict
        // concurrency checker rejects, and a bool NSNumber IS a CFBoolean.
        let value = NSNumber(value: true) as CFTypeRef
        let err = AXGuard.measure(pid: ref.pid) {
            AXUIElementSetAttributeValue(element, Self.attribute, value)
        }
        guard err == .success else {
            QLog.notice(.ax, "AXManualAccessibility rejected by \(ref.bundleID ?? "unknown") (\(err.rawValue))")
            return false
        }
        appliedPIDs.insert(ref.pid)
        QLog.info(.ax, "AXManualAccessibility set for \(ref.bundleID ?? "unknown")")
        return true
    }

    /// "Improve compatibility" was just switched on in Settings — apply to
    /// every running copy right away, so the user doesn't have to relaunch.
    func applyNow(bundleID: String) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            apply(to: app)
        }
    }

    // MARK: - Hooks

    /// The focused element had no readable text. In an Electron app that is
    /// exactly the symptom the flag fixes, so try once per process.
    func noteEmptyRead() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier, bundleID != Constants.bundleID
        else { return }
        let pid = app.processIdentifier
        guard !appliedPIDs.contains(pid), !attemptedPIDs.contains(pid) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastEmptyReadAt[pid], now - last < Self.emptyReadInterval { return }
        lastEmptyReadAt[pid] = now

        let ref = Self.ref(for: app)
        guard isElectron(ref) else { return }
        let resolved = ProfileStore.shared.resolve(bundleID: bundleID, host: nil)
        let allowed: Bool
        switch resolved.improveCompatibility {
        case .some(true):  allowed = true
        case .some(false): allowed = false
        // Never chosen: auto-apply, except in editors it would put into
        // screen-reader mode.
        case nil:          allowed = !KnownApps.isShortcutReservedEditor(bundleID)
        }
        guard allowed else { return }

        attemptedPIDs.insert(pid)
        guard apply(to: ref) else { return }
        guard resolved.improveCompatibility == nil else { return }
        // Remember, so the next launch of that app gets it before the first
        // failed read. The app's profile stays at "inherit".
        rememberAutoApplied(bundleID)
    }

    private func rememberAutoApplied(_ bundleID: String) {
        guard autoAppliedBundleIDs.insert(bundleID).inserted else { return }
        QalamDefaults.suite.set(Array(autoAppliedBundleIDs).sorted(), forKey: Self.autoAppliedKey)
    }

    private func appAppeared(_ ref: AppRef?) {
        guard let ref, let bundleID = ref.bundleID, bundleID != Constants.bundleID,
              !appliedPIDs.contains(ref.pid)
        else { return }
        // What the user explicitly asked for, plus an app this Mac already
        // auto-applied to in an earlier session — the flag lives in the target
        // process, so a relaunch loses it. An explicit Off (`.some(false)`)
        // still wins, exactly as it does in `noteEmptyRead`.
        let resolved = ProfileStore.shared.resolve(bundleID: bundleID, host: nil).improveCompatibility
        guard resolved == true || (resolved == nil && autoAppliedBundleIDs.contains(bundleID))
        else { return }
        apply(to: ref)
    }

    private func appTerminated(_ pid: pid_t?) {
        guard let pid else { return }
        appliedPIDs.remove(pid)
        attemptedPIDs.remove(pid)
        lastEmptyReadAt.removeValue(forKey: pid)
    }

    // MARK: - Refs

    nonisolated private static func ref(for app: NSRunningApplication) -> AppRef {
        AppRef(pid: app.processIdentifier,
               bundleID: app.bundleIdentifier,
               bundlePath: app.bundleURL?.path,
               name: app.localizedName)
    }

    nonisolated private static func ref(from note: Notification) -> AppRef? {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return nil }
        return ref(for: app)
    }
}
