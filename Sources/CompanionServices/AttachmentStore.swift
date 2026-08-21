import CompanionCore
import CoreGraphics
import Foundation
import ImageIO

public final class AttachmentStore: AttachmentStoring, Sendable {
    private let root: URL
    private let maxBytes: Int

    public init(root: URL, maxBytes: Int = AttachmentPolicy.maxBytes) {
        self.root = root
        self.maxBytes = maxBytes
    }

    public func adopt(_ source: URL, conversationId: String) throws -> AttachmentRef {
        let size = try byteCount(at: source)
        try checkSize(size)
        let id = UUID()
        let dest = try destination(id: id, name: source.lastPathComponent, conversationId: conversationId)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            throw AttachmentError.io
        }
        return AttachmentRef(
            name: AttachmentPolicy.sanitizedFileName(source.lastPathComponent),
            path: dest.path,
            kind: AttachmentPolicy.kind(forExtension: source.pathExtension),
            byteCount: size,
            id: id)
    }

    public func adopt(imageData: Data, name: String, conversationId: String) throws -> AttachmentRef {
        try checkSize(imageData.count)
        let id = UUID()
        let dest = try destination(id: id, name: name, conversationId: conversationId)
        do {
            try imageData.write(to: dest, options: .atomic)
        } catch {
            throw AttachmentError.io
        }
        return AttachmentRef(
            name: AttachmentPolicy.sanitizedFileName(name),
            path: dest.path,
            kind: .image,
            byteCount: imageData.count,
            id: id)
    }

    public func restore(path: String) -> AttachmentRef? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard isUnderRoot(url) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              !isDir.boolValue
        else { return nil }
        let size: Int
        do {
            size = try byteCount(at: url)
        } catch {
            return nil
        }
        let stored = url.lastPathComponent
        return AttachmentRef(
            name: AttachmentPolicy.originalName(fromStored: stored),
            path: url.path,
            kind: AttachmentPolicy.kind(forExtension: url.pathExtension),
            byteCount: size)
    }

    public func discard(_ ref: AttachmentRef) {
        let url = URL(fileURLWithPath: ref.path).standardizedFileURL
        guard isUnderRoot(url) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Log.chat("failed to discard attachment")
        }
    }

    public func payload(for ref: AttachmentRef) -> AttachmentPayload? {
        switch AttachmentPolicy.delivery(for: ref) {
        case .imageDataURL:
            return imagePayload(ref)
        case .inlineText:
            return textPayload(ref)
        case .pathOnly:
            return .path(ref.path)
        }
    }

    public func thumbnailData(for ref: AttachmentRef) -> Data? {
        guard ref.kind == .image else { return nil }
        return jpegData(
            from: URL(fileURLWithPath: ref.path),
            maxEdge: AttachmentPolicy.thumbnailEdge)
    }

    private func imagePayload(_ ref: AttachmentRef) -> AttachmentPayload? {
        let url = URL(fileURLWithPath: ref.path)
        let ext = AttachmentPolicy.ext(of: ref)
        let mime = AttachmentPolicy.mime(forExtension: ext)
        if let pixels = pixelSize(at: url) {
            let scaled = AttachmentPolicy.scaledSize(
                width: pixels.width, height: pixels.height)
            if scaled.width != pixels.width || scaled.height != pixels.height,
               let jpeg = jpegData(from: url, maxEdge: AttachmentPolicy.maxImageEdge)
            {
                return .imageDataURL(
                    "data:image/jpeg;base64,\(jpeg.base64EncodedString())")
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return nil
        }
        guard !data.isEmpty else { return nil }
        return .imageDataURL(
            "data:\(mime);base64,\(data.base64EncodedString())")
    }

    private func textPayload(_ ref: AttachmentRef) -> AttachmentPayload? {
        let raw: String
        do {
            raw = try String(
                contentsOf: URL(fileURLWithPath: ref.path), encoding: .utf8)
        } catch {
            return nil
        }
        return .text(AttachmentPolicy.clipInline(raw))
    }

    private func destination(
        id: UUID, name: String, conversationId: String
    ) throws -> URL {
        guard AttachmentPolicy.isSafeConversationID(conversationId) else {
            throw AttachmentError.io
        }
        let dir = root.appendingPathComponent(conversationId, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            throw AttachmentError.io
        }
        return dir.appendingPathComponent(
            AttachmentPolicy.storedFileName(id: id, original: name))
    }

    private func checkSize(_ size: Int) throws {
        if size <= 0 { throw AttachmentError.unreadable }
        if size > maxBytes { throw AttachmentError.tooLarge }
    }

    private func byteCount(at url: URL) throws -> Int {
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw AttachmentError.unreadable
        }
        guard let size = (attrs[.size] as? NSNumber)?.intValue else {
            throw AttachmentError.unreadable
        }
        return size
    }

    private func isUnderRoot(_ url: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func pixelSize(at url: URL) -> (width: Double, height: Double)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Double,
              let height = props[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        return (width, height)
    }

    private func jpegData(from url: URL, maxEdge: Double) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxEdge),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary)
        else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            dest, image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
