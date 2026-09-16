import Foundation
import AppKit

/// Only one QalamAI may run: two copies would install two keystroke taps
/// (double-accepting every Tab) and fight over the bundled engine.
@MainActor
enum SingleInstance {
    /// Set when this process is the duplicate and is about to exit.
    static private(set) var isDuplicate = false

    /// Local IPC (no payload) asking the running copy to show itself.
    static let activateNotification = Notification.Name("com.qalamai.app.activateExisting")

    /// How long to wait for an instance that is still quitting (Quit, then
    /// relaunch right away — the old process stays listed while
    /// `applicationWillTerminate` stops the engine).
    private static let quitGracePeriod: TimeInterval = 1.5

    /// Returns true when this process should keep launching. If an older copy
    /// is running, activates it and exits immediately with `exit(0)` — NOT
    /// `NSApp.terminate`, so `applicationWillTerminate` can never kill the
    /// other copy's engine when both run from the same bundle path.
    static func enforce() -> Bool {
        guard !olderInstances().isEmpty else { return true }

        let deadline = Date().addingTimeInterval(quitGracePeriod)
        while !olderInstances().isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let other = olderInstances().first else { return true }

        isDuplicate = true
        QLog.notice(.app, "another instance is running (pid \(other.processIdentifier)) — activating it and exiting")
        QLog.flush()
        other.activate(options: [])
        DistributedNotificationCenter.default().postNotificationName(
            activateNotification, object: nil, userInfo: nil, deliverImmediately: true)
        exit(0)
    }

    /// The running copy pops its menu bar popover when a duplicate launch asks.
    static func observeActivationRequests() {
        DistributedNotificationCenter.default().addObserver(
            forName: activateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                MenuBarController.shared.flashAndShow()
            }
        }
    }

    /// Other live instances that launched before this one. Comparing launch
    /// order means two copies started at the same moment don't both exit —
    /// the newer one yields to the older.
    private static func olderInstances() -> [NSRunningApplication] {
        let me = NSRunningApplication.current
        let myLaunch = me.launchDate ?? Date()
        return NSRunningApplication.runningApplications(withBundleIdentifier: Constants.bundleID)
            .filter { other in
                guard other.processIdentifier != me.processIdentifier, !other.isTerminated else { return false }
                let otherLaunch = other.launchDate ?? .distantPast
                if otherLaunch != myLaunch { return otherLaunch < myLaunch }
                return other.processIdentifier < me.processIdentifier
            }
    }
}
