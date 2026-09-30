import AppKit
import CoreGraphics
import Foundation
import WebKit

/// The 2x PNG exports of a drawn diagram (16m-5b): snapshots of the same
/// page, at exact pixel dimensions and in sRGB whatever the screen is.
///
/// WebKit's public snapshot has no alpha, so the transparent export is made
/// by difference matting: the page shot once on white and once on black. A
/// pixel that shows through is white in one and black in the other; a solid
/// one is the same in both. That gives the alpha, and the black shot IS the
/// premultiplied colour. Exact for antialiased edges, no private API.
@MainActor
enum DiagramPNG {
    static let scale = 2.0

    static func withBackground(of view: WKWebView, width: Double, height: Double) async throws -> Data? {
        guard let shot = try await snapshot(of: view, width: width, height: height) else { return nil }
        return png(from: shot)
    }

    static func transparent(of view: WKWebView, width: Double, height: Double) async throws -> Data? {
        try await paint(view, "#ffffff")
        let white = try await snapshot(of: view, width: width, height: height)
        try await paint(view, "#000000")
        let black = try await snapshot(of: view, width: width, height: height)
        guard let white, let black, let matted = await matteAsync(onWhite: white, onBlack: black) else { return nil }
        return png(from: matted)
    }

    private static func paint(_ view: WKWebView, _ color: String) async throws {
        _ = try await view.evaluateJavaScript(
            "document.documentElement.style.background='\(color)';document.body.style.background='\(color)'")
        // The next frame carries the new colour into the snapshot.
        try await Task.sleep(for: .milliseconds(120))
    }

    private static func snapshot(of view: WKWebView, width: Double, height: Double) async throws -> CGImage? {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: height)
        config.snapshotWidth = NSNumber(value: width * scale)
        let image = try await view.takeSnapshot(configuration: config)
        return bitmap(of: image, pixelsWide: Int((width * scale).rounded()), pixelsHigh: Int((height * scale).rounded()))
    }

    private static func context(_ width: Int, _ height: Int) -> CGContext? { DiagramMatte.context(width, height) }

    /// Redrawn into sRGB at the exact size the export promises (a snapshot
    /// comes at the screen's backing scale, 2x what `snapshotWidth` says).
    static func bitmap(of image: NSImage, pixelsWide: Int, pixelsHigh: Int) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh)
        guard pixelsWide > 0, pixelsHigh > 0, let context = context(pixelsWide, pixelsHigh),
              let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        context.draw(source, in: rect)
        return context.makeImage()
    }

    /// The matte off the main actor: six million pixels for a 3000-point
    /// diagram is seconds of loop in a debug build, and the island must stay
    /// live while it runs.
    /// `onRun` is a per-call probe so a test sees only its own run, never one
    /// from a parallel test.
    static func matteAsync(onWhite white: CGImage, onBlack black: CGImage,
                           onRun: (@Sendable (Bool) -> Void)? = nil) async -> CGImage? {
        let shots = MatteShots(white: white, black: black)
        return await Task.detached(priority: .userInitiated) {
            DiagramMatte.matte(onWhite: shots.white, onBlack: shots.black, onRun: onRun)
        }.value
    }

    /// Kept for callers on the main actor with small images (tests).
    static func matte(onWhite white: CGImage, onBlack black: CGImage) -> CGImage? {
        DiagramMatte.matte(onWhite: white, onBlack: black)
    }

    static func png(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// Two CGImages handed to a detached task. They are immutable bitmaps that
/// nothing else touches while the matte reads them.
private struct MatteShots: @unchecked Sendable {
    let white: CGImage
    let black: CGImage
}

/// The pure part of the transparent export: no main actor, no WebKit.
enum DiagramMatte {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    static func context(_ width: Int, _ height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// alpha = 1 - (white - black) / 255; premultiplied colour = black.
    /// `onRun` is a test probe: told whether the loop is running on the main thread.
    static func matte(onWhite white: CGImage, onBlack black: CGImage,
                      onRun: (@Sendable (Bool) -> Void)? = nil) -> CGImage? {
        onRun?(Thread.isMainThread)
        let width = black.width, height = black.height
        guard white.width == width, white.height == height,
              let w = context(width, height), let b = context(width, height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        w.draw(white, in: rect)
        b.draw(black, in: rect)
        guard let whiteData = w.data, let blackData = b.data else { return nil }
        let whitePixels = whiteData.assumingMemoryBound(to: UInt8.self)
        let blackPixels = blackData.assumingMemoryBound(to: UInt8.self)
        var at = 0
        let end = width * height * 4
        while at < end {
            // Straight arithmetic: this runs once per pixel.
            let spread = (Int(whitePixels[at]) - Int(blackPixels[at]))
                + (Int(whitePixels[at + 1]) - Int(blackPixels[at + 1]))
                + (Int(whitePixels[at + 2]) - Int(blackPixels[at + 2]))
            let alpha = UInt8(max(0, min(255, 255 - spread / 3)))
            blackPixels[at + 3] = alpha
            // Premultiplied colour cannot exceed alpha.
            if blackPixels[at] > alpha { blackPixels[at] = alpha }
            if blackPixels[at + 1] > alpha { blackPixels[at + 1] = alpha }
            if blackPixels[at + 2] > alpha { blackPixels[at + 2] = alpha }
            at += 4
        }
        return b.makeImage()
    }
}
