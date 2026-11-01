import AppKit
import ScreenCaptureKit

enum ScreenCapture {
    enum Failure: LocalizedError {
        case displayNotFound
        var errorDescription: String? { "Không tìm thấy màn hình" }
    }

    /// Captures `rect` (points, top-left origin, relative to `screen`).
    static func image(of rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let displayID = screen.deviceDescription[key] as? CGDirectDisplayID
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Failure.displayNotFound
        }
        let ownApp = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        // At least 2x even on non-Retina screens: small text reads noticeably better.
        let scale = max(screen.backingScaleFactor, 2)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int(rect.width * scale)
        configuration.height = Int(rect.height * scale)
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
