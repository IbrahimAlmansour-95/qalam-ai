import Foundation
import AppKit
import CoreGraphics
@preconcurrency import Vision
import ScreenCaptureKit

/// Captures a band of the screen around the caret and OCRs it for "visual
/// context" — useful in apps whose text isn't exposed through the
/// Accessibility API. Opt-in and gated behind Screen Recording permission.
/// Off by default.
///
/// Only the window being typed in is captured (plus that app's menus and
/// popovers over it): never QalamAI's own panels (the ghost text would be
/// read back as context), never another app's window that sits in the band
/// (a notification banner, a password manager, a different browser), and
/// never the app's other windows, which would show through wherever another
/// app covers them. Nothing is captured in a password field, while Secure
/// Input is on, when that app is a password manager, or in Notification
/// Center / Spotlight.
actor ScreenOCRContext {
    static let shared = ScreenOCRContext()

    /// Throttle: at most one capture every N seconds, cached between calls so
    /// rapid keystrokes don't trigger a screenshot storm.
    private var lastCaptureAt: Date = .distantPast
    private var cachedText: String = ""
    /// The app `cachedText` was read for — it is never served to another app.
    /// The bundle id too: Chrome apps (PWAs) share the browser's field pid.
    private var cachedPID: pid_t = 0
    private var cachedBundleID: String?
    private let minInterval: TimeInterval = 2.5

    private init() {}

    // MARK: - Permission

    nonisolated func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    nonisolated func requestPermission() {
        // Triggers the system prompt + adds the app to the Screen Recording list.
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Context

    /// Returns bounded OCR text from a band around `caretScreenRect` (AppKit
    /// screen coords), read from the window being typed in only: the one at
    /// the caret owned by `pid` (the field's app) or `frontPID` (the frontmost
    /// app). Cached and throttled. Returns "" when unavailable, and without
    /// capturing when `isSecure` (password field / Secure Input), when
    /// `bundleID` or either app is a password manager or Notification Center /
    /// Spotlight, or when `pid` is QalamAI itself.
    func visualContext(around caretScreenRect: CGRect?,
                       pid: pid_t,
                       frontPID: pid_t,
                       bundleID: String?,
                       isSecure: Bool,
                       maxChars: Int = 500) async -> String {
        guard hasPermission() else { return "" }
        guard !isSecure, pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              !KnownApps.isPasswordManager(bundleID), !KnownApps.showsOtherAppsContent(bundleID)
        else { return "" }
        if Date().timeIntervalSince(lastCaptureAt) < minInterval {
            return cached(for: pid, bundleID: bundleID)
        }
        lastCaptureAt = Date()

        switch await capture(around: caretScreenRect, pid: pid, frontPID: frontPID) {
        case .image(let image):
            let text = await Self.ocr(image, maxChars: maxChars, keepEnd: caretScreenRect != nil)
            if !text.isEmpty {
                cachedText = text
                cachedPID = pid
                cachedBundleID = bundleID
            }
            return cached(for: pid, bundleID: bundleID)
        case .sensitive:
            return ""
        case .unavailable:
            return cached(for: pid, bundleID: bundleID)
        }
    }

    private func cached(for pid: pid_t, bundleID: String?) -> String {
        cachedPID == pid && cachedBundleID == bundleID ? cachedText : ""
    }

    // MARK: - Band geometry

    /// Points captured above the caret's line (the paragraph or thread being
    /// answered) and below it.
    static let bandAbove: CGFloat = 480
    static let bandBelow: CGFloat = 80

    /// What to capture on one display: `sourceRect` in display-local points
    /// with a top-left origin (what `SCStreamConfiguration.sourceRect` takes),
    /// and its size in pixels at the display's point→pixel scale.
    struct CaptureBand: Equatable, Sendable {
        let sourceRect: CGRect
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// The band to capture on one display — pure geometry. `displayFrame` and
    /// `caret` are AppKit global coordinates (bottom-left origin, y up; other
    /// displays can sit at negative or offset origins). Full display width,
    /// from `bandAbove` points above the caret down to `bandBelow` below it,
    /// clipped to the display and snapped outward to whole points. nil when
    /// the caret isn't on this display: a caret belongs to the display holding
    /// its midpoint, half-open so a shared edge picks exactly one. With no
    /// caret, a band of the same height centred on the part of `anchor` (the
    /// window being typed in, AppKit) on this display, or on the display, and
    /// kept on the display so it keeps its full height.
    nonisolated static func captureBand(displayFrame: CGRect, caret: CGRect?, scale: CGFloat,
                                        anchor: CGRect? = nil) -> CaptureBand? {
        let display = displayFrame.standardized
        guard display.minX.isFinite, display.minY.isFinite,
              display.width >= 1, display.width <= 100_000,
              display.height >= 1, display.height <= 100_000
        else { return nil }
        let pixelScale = scale.isFinite && scale > 0 ? min(scale, 4) : 1

        // Band edges, AppKit y (up).
        let top: CGFloat
        let bottom: CGFloat
        if let caret {
            let c = caret.standardized
            guard c.minX.isFinite, c.minY.isFinite, c.width.isFinite, c.height.isFinite,
                  c.midX >= display.minX, c.midX < display.maxX,
                  c.midY >= display.minY, c.midY < display.maxY
            else { return nil }
            top = c.maxY + bandAbove
            bottom = c.minY - bandBelow
        } else {
            let half = (bandAbove + bandBelow) / 2
            var centre = display.midY
            if display.height >= 2 * half {
                if let a = anchor?.standardized,
                   a.minX.isFinite, a.minY.isFinite, a.width.isFinite, a.height.isFinite {
                    let visible = a.intersection(display)
                    if !visible.isNull { centre = visible.midY }
                }
                centre = min(max(centre, display.minY + half), display.maxY - half)
            }
            top = centre + half
            bottom = centre - half
        }

        // Clip to the display, flip to display-local top-left, snap outward.
        let localTop = max(0, (display.maxY - min(top, display.maxY)).rounded(.down))
        let localBottom = min(display.height, (display.maxY - max(bottom, display.minY)).rounded(.up))
        guard localBottom > localTop else { return nil }
        let rect = CGRect(x: 0, y: localTop, width: display.width, height: localBottom - localTop)
        let pixelWidth = Int((rect.width * pixelScale).rounded())
        let pixelHeight = Int((rect.height * pixelScale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return CaptureBand(sourceRect: rect, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    /// A Quartz global rect (top-left origin at the primary display, y down —
    /// `CGDisplayBounds`, `SCWindow.frame`) in AppKit global coordinates: the
    /// same single flip `AccessibilityMonitor.caretFrame` applies to the caret.
    nonisolated static func appKitRect(fromQuartz rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// One on-screen window as `CGWindowListCopyWindowInfo` reports it.
    struct WindowEntry: Equatable, Sendable {
        let id: CGWindowID
        let pid: pid_t
        let layer: Int
        let bounds: CGRect   // Quartz global
    }

    /// The window being typed in, from `order` (front to back) — pure. The
    /// front-most window of a `candidates` app holding `point` (the caret
    /// midpoint, Quartz), looking past other apps' floating windows
    /// (notification banners, menus) but not past another app's normal
    /// window: the field is then in a window we can't attribute, and what is
    /// behind it isn't visible. A floating hit (a popover over the caret, or
    /// a launcher panel) gives way to its own app's normal window under it.
    /// With no point, the candidates' front normal window.
    nonisolated static func targetWindow(in order: [WindowEntry], candidates: Set<pid_t>,
                                         at point: CGPoint?) -> WindowEntry? {
        guard let point else {
            return order.first { candidates.contains($0.pid) && $0.layer == 0 }
        }
        var floating: WindowEntry?
        for window in order where window.bounds.contains(point) {
            if let floating {
                if window.layer <= 0 { return window.pid == floating.pid ? window : floating }
            } else if candidates.contains(window.pid) {
                if window.layer <= 0 { return window }
                floating = window
            } else if window.layer <= 0 {
                return nil
            }
        }
        return floating
    }

    // MARK: - Capture (ScreenCaptureKit)

    private enum Capture {
        case image(CGImage)
        /// The app is a password manager or a system panel showing other
        /// apps' content (Notification Center, Spotlight): read nothing.
        case sensitive
        /// Nothing captured (app, window or display not resolvable, capture
        /// failed).
        case unavailable
    }

    /// Captures only the band, and only the window being typed in (with its
    /// app's menus and popovers over it) — other apps' windows, the app's
    /// other windows and QalamAI's own panels are simply not composited.
    private func capture(around caretScreenRect: CGRect?, pid: pid_t, frontPID: pid_t) async -> Capture {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                               onScreenWindowsOnly: true)
            // The window may belong to either app: a Chrome app (PWA) window is
            // owned by its app-shim process, the frontmost app, while its
            // fields report the browser's pid. Don't narrow this to `pid`.
            let own = ProcessInfo.processInfo.processIdentifier
            let candidates = Set([pid, frontPID].filter { $0 > 0 && $0 != own })
            let apps = content.applications.filter { candidates.contains($0.processID) }
            if apps.contains(where: {
                KnownApps.isPasswordManager($0.bundleIdentifier) || KnownApps.showsOtherAppsContent($0.bundleIdentifier)
            }) { return .sensitive }

            // Display bounds and window frames are Quartz global coordinates;
            // the caret is AppKit.
            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            let caretPoint = caretScreenRect.map { CGPoint(x: $0.midX, y: primaryHeight - $0.midY) }
            // If the window or its app can't be resolved, capture nothing —
            // never fall back to more windows or the whole display.
            guard let entry = Self.targetWindow(in: Self.windowsFrontToBack(excluding: own),
                                                candidates: candidates, at: caretPoint),
                  apps.contains(where: { $0.processID == entry.pid }),
                  let target = content.windows.first(where: { $0.windowID == entry.id })
            else { return .unavailable }
            // A filter draws only what it includes, so any other window of the
            // app would show through wherever another app covers it.
            let windows = content.windows.filter {
                $0.windowID == target.windowID
                    || ($0.owningApplication?.processID == entry.pid
                        && $0.windowLayer > target.windowLayer && $0.frame.intersects(target.frame))
            }

            func appKitFrame(_ display: SCDisplay) -> CGRect {
                Self.appKitRect(fromQuartz: CGDisplayBounds(display.displayID), primaryHeight: primaryHeight)
            }
            // The display holding the caret, or with no caret the window's
            // midpoint (else the one showing the most of the window).
            let targetFrame = Self.appKitRect(fromQuartz: target.frame, primaryHeight: primaryHeight)
            let probe = caretScreenRect ?? CGRect(x: targetFrame.midX, y: targetFrame.midY, width: 0, height: 0)
            var display = content.displays.first {
                Self.captureBand(displayFrame: appKitFrame($0), caret: probe, scale: 1) != nil
            }
            if display == nil, caretScreenRect == nil {
                func overlap(_ d: SCDisplay) -> CGFloat {
                    let r = target.frame.intersection(CGDisplayBounds(d.displayID))
                    return r.isNull ? 0 : r.width * r.height
                }
                display = content.displays.filter { overlap($0) > 0 }.max { overlap($0) < overlap($1) }
            }
            guard let display else { return .unavailable }

            let filter = SCContentFilter(display: display, including: windows)
            // Capture at 1 pixel per point, the resolution OCR has always used:
            // Vision reads body text fine at 1x, and Retina 2x would quadruple
            // the pixels captured and recognised on every refresh.
            guard let band = Self.captureBand(displayFrame: appKitFrame(display),
                                              caret: caretScreenRect,
                                              scale: 1,
                                              anchor: targetFrame)
            else { return .unavailable }
            let config = SCStreamConfiguration()
            config.sourceRect = band.sourceRect
            config.width = band.pixelWidth
            config.height = band.pixelHeight
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                   configuration: config)
            return .image(image)
        } catch {
            return .unavailable
        }
    }

    /// On-screen windows front to back, without QalamAI's own or invisible
    /// ones. CGWindow.h documents this order; SCShareableContent's is
    /// undocumented. Reads only ids, owners, layers and bounds.
    private static func windowsFrontToBack(excluding own: pid_t) -> [WindowEntry] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return ((list as? [[String: Any]]) ?? []).compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { return nil }
            return WindowEntry(id: id, pid: pid, layer: layer, bounds: bounds)
        }
    }

    // MARK: - OCR (Vision)

    /// Top-to-bottom lines, bounded to `maxChars` from the end when `keepEnd`
    /// (a caret band, whose last lines are nearest the caret) else the start.
    private static func ocr(_ image: CGImage, maxChars: Int, keepEnd: Bool) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { req, _ in
                    let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                    let lines = observations
                        .sorted {
                            abs($0.boundingBox.minY - $1.boundingBox.minY) > 0.02
                                ? $0.boundingBox.minY > $1.boundingBox.minY
                                : $0.boundingBox.minX < $1.boundingBox.minX
                        }
                        .compactMap { $0.topCandidates(1).first?.string }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let joined = lines.joined(separator: "\n")
                    let text = keepEnd ? String(joined.suffix(maxChars)) : String(joined.prefix(maxChars))
                    continuation.resume(returning: text)
                }
                request.recognitionLevel = .fast
                request.usesLanguageCorrection = false
                // English + Arabic, matching the rest of the app.
                request.recognitionLanguages = ["en-US", "ar-SA"]
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                try? handler.perform([request])
            }
        }
    }
}
