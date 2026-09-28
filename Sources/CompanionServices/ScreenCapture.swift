import CompanionCore
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// One JPEG of a display, without our own windows. Never a stream.
public struct ScreenCapture: Sendable {
    private let bundleID: String
    private let trusted: @Sendable () -> Bool
    private let grab: (@Sendable () async -> Data?)?

    public init(
        bundleID: String,
        trusted: @escaping @Sendable () -> Bool,
        grab: (@Sendable () async -> Data?)? = nil
    ) {
        self.bundleID = bundleID
        self.trusted = trusted
        self.grab = grab
    }

    /// Text on a Retina display does not survive 1280 px; the per-turn sidecar
    /// does not read text, `see` does.
    public static let seeMaxSide: CGFloat = 2_000
    public static let sidecarMaxSide: CGFloat = 1_280

    /// `pid` picks the display holding that process's window; without it, or
    /// when it has no window on screen, the main display.
    public func jpeg(pid: Int32? = nil, maxSide: CGFloat = sidecarMaxSide) async -> Data? {
        guard trusted() else { return nil }
        if let grab { return await grab() }
        return await Self.take(excluding: bundleID, pid: pid, maxSide: maxSide)
    }

    static func take(excluding bundleID: String, pid: Int32?, maxSide: CGFloat) async -> Data? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            let window = pid.flatMap { pid in
                content.windows.filter {
                    $0.owningApplication?.processID == pid && $0.windowLayer == 0
                }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            }
            let picked = DisplayPick.index(of: window?.frame, in: content.displays.map(\.frame))
            guard let display = picked.map({ content.displays[$0] })
                ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else { return nil }
            let excluded = content.applications.filter { $0.bundleIdentifier == bundleID }
            let filter = SCContentFilter(
                display: display, excludingApplications: excluded, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let width = CGFloat(display.width)
            let height = CGFloat(display.height)
            let scale = min(1, maxSide / max(width, height))
            config.width = Int((width * scale).rounded())
            config.height = Int((height * scale).rounded())
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            return jpeg(image, quality: 0.7)
        } catch {
            return nil
        }
    }

    static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            dest, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
