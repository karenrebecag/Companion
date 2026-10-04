import CompanionCore
import CoreGraphics
import Foundation
import ImageIO

// Wave 16m-3: what the island shows of the staged attachments, decided
// before anything is painted. Files are Incredible's 84 × 102 cards in the
// order they were attached; the clip's captures gather in one 96 × 64 stack
// with their count, which opens into the strip.

/// A file the island tried to stage and could not (too large, unreadable).
/// It stays as a card in error until taken back or sent past, because the
/// window's toast is not on screen when the island did the attaching.
package struct IslandAttachFailure: Sendable, Equatable, Identifiable {
    package let id: UUID
    package let name: String
    /// Why it was refused, in the user's words; nil when the cause is unknown.
    package let reason: String?

    /// Named the way a staged file is: no path, no direction controls.
    package init(name: String, reason: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.name = AttachmentPolicy.sanitizedFileName(name)
        self.reason = reason
    }

    package static func removing(_ id: UUID, from failures: [IslandAttachFailure]) -> [IslandAttachFailure] {
        failures.filter { $0.id != id }
    }
}

/// One card in the chip row.
package enum IslandAttachCardItem: Sendable, Equatable, Identifiable {
    case staged(AttachmentRef)
    case failed(IslandAttachFailure)

    package var id: UUID {
        switch self {
        case .staged(let ref): ref.id
        case .failed(let failure): failure.id
        }
    }

    package var name: String {
        switch self {
        case .staged(let ref): ref.name
        case .failed(let failure): failure.name
        }
    }

    package var failureReason: String? {
        if case .failed(let failure) = self { return failure.reason }
        return nil
    }

    package var isError: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// The captures folded into one tile: the newest on top.
package struct IslandCaptureStackModel: Sendable, Equatable {
    package let top: AttachmentRef
    package let count: Int

    /// Incredible counts only when there is more than the one on view.
    package var badge: String? { count > 1 ? String(count) : nil }

    /// The cards peeking out under the top one.
    package var layers: Int { min(count - 1, IslandAttachMetrics.stackLayers) }

    /// The tile plus the room its peeking layers take to the side.
    package var width: CGFloat {
        IslandAttachMetrics.stackWidth + CGFloat(layers) * IslandAttachMetrics.stackOffset
    }
}

package struct IslandAttachTrayModel: Sendable, Equatable {
    package let stack: IslandCaptureStackModel?
    /// The captures laid out one by one once the stack is opened.
    package let strip: [AttachmentRef]
    package let cards: [IslandAttachCardItem]

    package var isEmpty: Bool { stack == nil && strip.isEmpty && cards.isEmpty }

    package static func project(
        staged: [AttachmentRef], failed: [IslandAttachFailure], expanded: Bool
    ) -> IslandAttachTrayModel {
        let captures = staged.filter { RegionCapture.isCapture(name: $0.name) }.reversed().map { $0 }
        let files = staged.filter { !RegionCapture.isCapture(name: $0.name) }
        let cards = files.map(IslandAttachCardItem.staged) + failed.map(IslandAttachCardItem.failed)
        let opened = expanded && captures.count > 1
        let stack = opened ? nil : captures.first.map { IslandCaptureStackModel(top: $0, count: captures.count) }
        return IslandAttachTrayModel(stack: stack, strip: opened ? captures : [], cards: cards)
    }

    /// The chip row's natural width: the stack, the cards, the gaps between
    /// them and the measured trailing padding.
    package var rowWidth: CGFloat {
        let widths = (stack.map { [$0.width] } ?? [])
            + cards.map { _ in IslandAttachMetrics.cardWidth }
        guard !widths.isEmpty else { return 0 }
        let gaps = CGFloat(widths.count - 1) * IslandAttachMetrics.rowGap
        return widths.reduce(0, +) + gaps + IslandAttachMetrics.rowPaddingTrailing
    }

    /// Only a row that runs past the island fades at its end; a short one
    /// would lose its last card's edge for nothing.
    package func overflows(available: CGFloat) -> Bool {
        rowWidth > available
    }
}

package enum IslandAttachLabel {
    /// The extension badge: the file's type in capitals, or none at all.
    package static func ext(_ name: String) -> String? {
        let ext = URL(fileURLWithPath: name).pathExtension
        return ext.isEmpty ? nil : ext.uppercased()
    }
}

/// The picture a card bleeds to. Read with ImageIO from the stored local
/// copy, downsampled to what the card draws: never a network read, never a
/// Quick Look plug-in parsing an arbitrary file, never a full decode of a
/// photo just to show 84 points of it.
package enum IslandAttachThumbnail {
    nonisolated package static func make(
        path: String, maxPixel: CGFloat, maxSourcePixels: CGFloat = IslandAttachMetrics.maxSourcePixels
    ) -> CGImage? {
        guard path.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: path)
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, noCache),
              fitsDecoding(source, maxSourcePixels: maxSourcePixels) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// The header's declared canvas, read before any pixel is decoded: a
    /// file claiming a gigantic canvas is refused, and so is one that does
    /// not say (security review 16m-3, LOW-1).
    nonisolated static func fitsDecoding(_ source: CGImageSource, maxSourcePixels: CGFloat) -> Bool {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        else { return false }
        return CGFloat(width * height) <= maxSourcePixels
    }
}

/// One decode per attachment. SwiftUI rebuilds a card whenever the tray
/// changes; without this every rebuild decoded its picture again (review
/// 16m-3). A failed decode is remembered too, or it would be retried as often.
nonisolated package final class IslandThumbnailCache: @unchecked Sendable {
    package static let shared = IslandThumbnailCache(decode: { path, pixels in
        IslandAttachThumbnail.make(path: path, maxPixel: pixels)
    })

    private final class Entry {
        let image: CGImage?
        init(_ image: CGImage?) { self.image = image }
    }

    // NSCache is thread-safe and gives memory back under pressure on its own.
    private let cache = NSCache<NSUUID, Entry>()
    private let decode: @Sendable (String, CGFloat) -> CGImage?

    package init(decode: @escaping @Sendable (String, CGFloat) -> CGImage?) {
        self.decode = decode
        cache.countLimit = IslandAttachMetrics.thumbnailCacheLimit
    }

    package func image(id: UUID, path: String) -> CGImage? {
        if let hit = cache.object(forKey: id as NSUUID) { return hit.image }
        let image = decode(path, IslandAttachMetrics.thumbnailPixels)
        cache.setObject(Entry(image), forKey: id as NSUUID)
        return image
    }
}

/// What a picture tile shows: nothing while it loads, the picture, or the
/// file's icon when it could not be read — never an empty hole.
package enum IslandPictureState: Equatable {
    case loading, picture, fallback

    package static func of(image: CGImage?, loaded: Bool) -> IslandPictureState {
        if image != nil { return .picture }
        return loaded ? .fallback : .loading
    }
}
