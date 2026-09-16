import Foundation
import AppKit
import ApplicationServices

/// Keeps a hung or very slow app from freezing QalamAI.
///
/// Every AX call we make runs on the main thread, which also services the
/// keystroke CGEventTap. With the system default messaging timeout (~6 s per
/// call) and 6–15 calls per keystroke, one beach-balled app could stall the
/// main thread — and with it system-wide typing — for tens of seconds.
///
/// Two layers:
///   * `messagingTimeout` (0.5 s) caps every single AX message. Healthy replies
///     take 1–50 ms and heavy WebKit / Office text-marker queries ~100–200 ms,
///     so 0.5 s leaves ≥2.5× headroom and doesn't make working caret placement
///     fail. (The very first query into a Chromium/Electron app that hasn't
///     built its AX tree yet can miss once; the next keystroke succeeds.)
///   * A per-pid breaker: two CONSECUTIVE measured blocks that take ≥ 0.45 s
///     stop all AX IPC to that app for 3 s. One legitimately slow block (the
///     full value of a huge document) never trips it; a hung app hits the
///     timeout on every block, so it trips on the second one — worst case
///     ≈1 s of hitches, then 3 s of silence, and typing stays responsive.
/// Gating happens at CALL SITES; the caret/field readers themselves are
/// untouched.
@MainActor
enum AXGuard {
    /// Seconds a single AX message may take before it fails with
    /// `kAXErrorCannotComplete`.
    static let messagingTimeout: Float = 0.5
    /// A measured block at or above this counts as "slow".
    static let slowCallThreshold: TimeInterval = 0.45
    /// How long AX IPC to a tripped pid is skipped.
    static let backoff: TimeInterval = 3

    private static var slowStreak: [pid_t: Int] = [:]
    private static var backedOffUntil: [pid_t: TimeInterval] = [:]

    /// Sets the process-wide AX timeout. Per the AXUIElement docs, setting it
    /// on the system-wide element applies globally to every element this
    /// process creates (including ones derived from the focused element).
    static func configureGlobalTimeout() {
        let err = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
        if err != .success {
            QLog.error(.ax, "AXUIElementSetMessagingTimeout failed (\(err.rawValue))")
        }
    }

    /// Same timeout on an element we create ourselves (e.g. an
    /// `AXUIElementCreateApplication` element). Elements default to the global
    /// value, so this only matters if something reset it.
    static func configure(_ element: AXUIElement) {
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeout)
    }

    /// Frontmost app pid from NSWorkspace — no AX IPC, safe anywhere.
    static func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    /// True while AX calls to `pid` should be skipped.
    static func isBackedOff(_ pid: pid_t?) -> Bool {
        guard let pid, let until = backedOffUntil[pid] else { return false }
        if ProcessInfo.processInfo.systemUptime < until { return true }
        backedOffUntil.removeValue(forKey: pid)
        return false
    }

    /// Number of apps whose AX IPC is currently paused (diagnostics). The
    /// frontmost app is usually QalamAI itself when this is read.
    static func activeBackoffCount() -> Int {
        let now = ProcessInfo.processInfo.systemUptime
        backedOffUntil = backedOffUntil.filter { $0.value > now }
        return backedOffUntil.count
    }

    /// Runs `body` (a block of AX calls against `pid`) and feeds its duration
    /// into the breaker.
    @discardableResult
    static func measure<T>(pid: pid_t?, _ body: () -> T) -> T {
        let start = ProcessInfo.processInfo.systemUptime
        let result = body()
        guard let pid else { return result }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - start
        if elapsed >= slowCallThreshold {
            let streak = (slowStreak[pid] ?? 0) + 1
            if streak >= 2 {
                slowStreak.removeValue(forKey: pid)
                backedOffUntil[pid] = now + backoff
                QLog.notice(.ax, "AX to pid \(pid) slow (\(String(format: "%.2f", elapsed))s) — pausing AX for \(Int(backoff))s")
            } else {
                slowStreak[pid] = streak
            }
        } else if slowStreak[pid] != nil {
            slowStreak.removeValue(forKey: pid)
        }
        return result
    }
}
