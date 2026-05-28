import Foundation
import AppKit
import CoreGraphics
@preconcurrency import Vision
import ScreenCaptureKit

/// Captures the display around the caret and OCRs it for "visual context" —
/// useful in apps whose text isn't exposed through the Accessibility API.
/// Opt-in and gated behind Screen Recording permission. Off by default.
actor ScreenOCRContext {
    static let shared = ScreenOCRContext()

    /// Throttle: at most one capture every N seconds, cached between calls so
    /// rapid keystrokes don't trigger a screenshot storm.
    private var lastCaptureAt: Date = .distantPast
    private var cachedText: String = ""
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

    /// Returns bounded OCR text from a region around `caretScreenRect` (AppKit
    /// screen coords). Cached/throttled. Returns "" when unavailable.
    func visualContext(around caretScreenRect: CGRect?, maxChars: Int = 500) async -> String {
        guard hasPermission() else { return "" }
        if Date().timeIntervalSince(lastCaptureAt) < minInterval {
            return cachedText
        }
        lastCaptureAt = Date()

        guard let image = await captureRegion(around: caretScreenRect) else {
            return cachedText
        }
        let text = await Self.ocr(image, maxChars: maxChars)
        if !text.isEmpty { cachedText = text }
        return cachedText
    }

    // MARK: - Capture (ScreenCaptureKit)

    private func captureRegion(around caretScreenRect: CGRect?) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                               onScreenWindowsOnly: true)
            // Pick the display containing the caret (or the main display).
            let display: SCDisplay?
            if let rect = caretScreenRect,
               let match = content.displays.first(where: { NSIntersectsRect($0.frame, rect) }) {
                display = match
            } else {
                display = content.displays.first
            }
            guard let display else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            // Capture a band around the caret to keep OCR fast; fall back to a
            // top region of the display when we don't have a caret rect.
            config.scalesToFit = true
            let scale = 1
            config.width = Int(display.width) / max(1, scale)
            config.height = Int(display.height) / max(1, scale)
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                   configuration: config)
            return crop(image, display: display, around: caretScreenRect)
        } catch {
            return nil
        }
    }

    /// Crops a band around the caret to bound OCR cost. ScreenCaptureKit images
    /// are top-left origin in pixels; convert from AppKit bottom-left points.
    private func crop(_ image: CGImage, display: SCDisplay, around caretScreenRect: CGRect?) -> CGImage {
        guard let caret = caretScreenRect else { return image }
        let scaleX = CGFloat(image.width) / display.frame.width
        let scaleY = CGFloat(image.height) / display.frame.height

        // Band: full width, from ~480pt above the caret down to ~80pt below.
        let bandTopPt = caret.maxY + 80
        let bandHeightPt: CGFloat = 560
        let originXpx: CGFloat = 0
        // Convert AppKit Y (bottom-left, relative to display) to image Y (top-left).
        let displayTopPt = display.frame.maxY
        let topYpx = (displayTopPt - bandTopPt) * scaleY
        let heightPx = bandHeightPt * scaleY

        let rect = CGRect(x: originXpx,
                          y: max(0, topYpx),
                          width: CGFloat(image.width),
                          height: min(CGFloat(image.height), heightPx))
        return image.cropping(to: rect) ?? image
    }

    // MARK: - OCR (Vision)

    private static func ocr(_ image: CGImage, maxChars: Int) async -> String {
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
                    let text = String(lines.joined(separator: "\n").prefix(maxChars))
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
