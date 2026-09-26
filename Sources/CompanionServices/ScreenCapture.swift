import CompanionCore
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// One JPEG of the main display, without our own windows. Never a stream.
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

    public func jpeg() async -> Data? {
        guard trusted() else { return nil }
        if let grab { return await grab() }
        return await Self.take(excluding: bundleID)
    }

    static func take(excluding bundleID: String) async -> Data? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: {
                $0.displayID == CGMainDisplayID()
            }) ?? content.displays.first else { return nil }
            let excluded = content.applications.filter { $0.bundleIdentifier == bundleID }
            let filter = SCContentFilter(
                display: display, excludingApplications: excluded, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let maxSide: CGFloat = 1280
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
