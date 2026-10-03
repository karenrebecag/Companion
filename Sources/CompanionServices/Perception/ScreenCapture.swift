import CompanionCore
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// One JPEG of a display, without our own windows. Never a stream.
package struct ScreenCapture: Sendable {
    private let bundleID: String
    private let trusted: @Sendable () -> Bool
    /// Gap 1: when wired, a capture runs only once one was verified, and
    /// every outcome tells the gate, so a lost grant turns sight off instead
    /// of failing silently on every turn.
    private let gate: ScreenRecordingGate?
    private let shoot: (@Sendable () async -> Shot)?
    private let log: @Sendable (String) -> Void

    package init(
        bundleID: String,
        trusted: @escaping @Sendable () -> Bool,
        gate: ScreenRecordingGate? = nil,
        grab: (@Sendable () async -> Data?)? = nil
    ) {
        let shoot: (@Sendable () async -> Shot)? = grab.map { grab in
            { @Sendable in await grab().map(Shot.image) ?? .failed("grab returned nothing") }
        }
        self.init(bundleID: bundleID, trusted: trusted, gate: gate, shoot: shoot)
    }

    init(
        bundleID: String,
        trusted: @escaping @Sendable () -> Bool,
        gate: ScreenRecordingGate?,
        shoot: (@Sendable () async -> Shot)?,
        log: @escaping @Sendable (String) -> Void = { Log.app($0) }
    ) {
        self.bundleID = bundleID
        self.trusted = trusted
        self.gate = gate
        self.shoot = shoot
        self.log = log
    }

    /// Text on a Retina display does not survive 1280 px; the per-turn sidecar
    /// does not read text, `see` does.
    package static let seeMaxSide: CGFloat = 2_000
    package static let sidecarMaxSide: CGFloat = 1_280

    /// `pid` picks the display holding that process's window; without it, or
    /// when it has no window on screen, the main display.
    package func jpeg(pid: Int32? = nil, maxSide: CGFloat = sidecarMaxSide) async -> Data? {
        guard trusted() else { return nil }
        if let gate, !gate.sightReady {
            guard await gate.reprobeIfDue() == .verified else { return nil }
        }
        let shot: Shot = if let shoot {
            await shoot()
        } else {
            await Self.take(excluding: bundleID, pid: pid, maxSide: maxSide)
        }
        switch shot {
        case .image(let data):
            gate?.captureSucceeded()
            return data
        case .failed(let cause):
            // The cause is the only trace of a revoked grant: without it the
            // sight just goes quiet.
            log("screen: capture failed (\(cause))")
            // Off the caller's path: a revoke is when the probe is likeliest
            // to stall, and the turn already has its answer (no image).
            if let gate { Task { await gate.captureFailed() } }
            return nil
        case .skipped:
            return nil
        }
    }

    /// A target with nothing to show is not a broken grant: only `failed`
    /// sends the gate back to probing.
    enum Shot: Sendable {
        case image(Data)
        case failed(String)
        case skipped
    }

    static func take(excluding bundleID: String, pid: Int32?, maxSide: CGFloat) async -> Shot {
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
                ?? content.displays.first else {
                return .failed("no display available")
            }
            let filter: SCContentFilter
            switch CaptureScope.of(pid: pid, ownPID: ProcessInfo.processInfo.processIdentifier) {
            case .nothing:
                return .skipped
            case .targetApp(let target):
                // Only the target's windows leave the Mac, not whatever else
                // shares its display (security review 20b).
                guard let app = content.applications.first(where: { $0.processID == target }) else {
                    return .skipped
                }
                filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            case .displayWithoutSelf:
                let excluded = content.applications.filter { $0.bundleIdentifier == bundleID }
                filter = SCContentFilter(
                    display: display, excludingApplications: excluded, exceptingWindows: [])
            }
            let config = SCStreamConfiguration()
            let width = CGFloat(display.width)
            let height = CGFloat(display.height)
            let scale = min(1, maxSide / max(width, height))
            config.width = Int((width * scale).rounded())
            config.height = Int((height * scale).rounded())
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            guard let data = jpeg(image, quality: 0.7) else {
                return .failed("jpeg encoding")
            }
            return .image(data)
        } catch {
            return .failed(error.localizedDescription)
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
