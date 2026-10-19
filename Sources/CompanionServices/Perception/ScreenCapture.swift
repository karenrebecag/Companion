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
        case .withheld(let reason):
            // Not a grant problem: the gate stays as it is, and the reason is
            // fixed text, never the frame or any field's content.
            log("screen: frame withheld (\(reason))")
            return nil
        }
    }

    /// A target with nothing to show is not a broken grant: only `failed`
    /// sends the gate back to probing.
    enum Shot: Sendable {
        case image(Data)
        case failed(String)
        case skipped
        /// The frame could not be proven free of secure fields: not sent.
        case withheld(String)
    }

    static func take(excluding bundleID: String, pid: Int32?, maxSide: CGFloat) async -> Shot {
        do {
            let ownPID = ProcessInfo.processInfo.processIdentifier
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
            let scope = CaptureScope.of(pid: pid, ownPID: ownPID)
            let filter: SCContentFilter
            let pids: [pid_t]
            switch scope {
            case .nothing:
                return .skipped
            case .targetApp(let target):
                // Only the target's windows leave the Mac, not whatever else
                // shares its display (security review 20b).
                guard let app = content.applications.first(where: { $0.processID == target }) else {
                    return .skipped
                }
                filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
                pids = [target]
            case .displayWithoutSelf:
                let excluded = content.applications.filter { $0.bundleIdentifier == bundleID }
                filter = SCContentFilter(
                    display: display, excludingApplications: excluded, exceptingWindows: [])
                // Any window on this display can show a password field, not
                // only the one in front, so every app drawn there is read.
                pids = Array(Set(content.windows
                    .filter { $0.frame.intersects(display.frame) }
                    .compactMap { $0.owningApplication?.processID })
                    .filter { $0 != ownPID })
            }
            let config = SCStreamConfiguration()
            let width = CGFloat(display.width)
            let height = CGFloat(display.height)
            let scale = min(1, maxSide / max(width, height))
            config.width = Int((width * scale).rounded())
            config.height = Int((height * scale).rounded())
            config.showsCursor = false
            // Overlay windows (Dock, Control Center) own AX trees that are
            // empty by design: only normal-layer windows make an app "shown".
            let owners = content.windows.compactMap { window in
                window.owningApplication.map { (pid: $0.processID, layer: window.windowLayer) }
            }
            let shown = SecureFieldMask.primaryOwners(owners)
            let enhanced = Set(content.applications
                .filter { AXScreen.chromiumBrowsers.contains($0.bundleIdentifier) }
                .map(\.processID))
            // A field can be in the pixels only if it existed at one of the
            // two reads, so the frame is masked with the union of both. The
            // first read finishes before the capture starts; the second follows
            // it. Starting it on another task could let it run after the frame
            // is already frozen.
            let before = SecureFieldReader.read(pids: pids, shown: shown, enhancedPIDs: enhanced)
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            let after = SecureFieldReader.read(pids: pids, shown: shown, enhancedPIDs: enhanced)
            return egress(
                image, display: display.frame,
                read: SecureFieldMask.union(before, after))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The only way a screen image becomes bytes for a vision provider. A
    /// frame whose secure fields cannot be masked is withheld, never sent
    /// unmasked (the AX text path already refuses secure fields, so the text
    /// fallback is safe).
    static func egress(_ image: CGImage, display: CGRect, read: SecureFieldMask.Read) -> Shot {
        switch SecureFieldMask.plan(
            read: read, display: display, imageWidth: image.width, imageHeight: image.height
        ) {
        case .withhold(let reason):
            return .withheld(reason)
        case .mask(let rects):
            guard let masked = paint(image, over: rects) else {
                return .withheld("mask could not be drawn")
            }
            guard let data = jpeg(masked, quality: 0.7) else {
                return .failed("jpeg encoding")
            }
            return .image(data)
        }
    }

    /// Opaque black over each rect, in image pixels counted from the top row.
    static func paint(_ image: CGImage, over rects: [CGRect]) -> CGImage? {
        guard !rects.isEmpty else { return image }
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for rect in rects {
            // The context counts rows from the bottom; the rects from the top.
            context.fill(CGRect(
                x: rect.minX, y: CGFloat(height) - rect.maxY,
                width: rect.width, height: rect.height))
        }
        return context.makeImage()
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
