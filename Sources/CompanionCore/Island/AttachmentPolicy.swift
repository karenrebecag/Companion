import Foundation

package enum AttachmentDelivery: Sendable, Equatable {
    case imageDataURL
    case inlineText
    case pathOnly
}

package enum AttachmentPayload: Sendable, Equatable {
    case imageDataURL(String)
    case text(String)
    case path(String)
}

package enum AttachmentError: Error, Sendable, Equatable {
    case tooLarge, unreadable, io
}

/// Decisions that must not touch disk. The store copies; this type decides
/// how the copy later travels to a model.
package enum AttachmentPolicy: Sendable {
    package static let maxBytes = 20 * 1024 * 1024
    package static let maxInlineChars = 40_000
    package static let maxImageEdge: Double = 1024
    package static let thumbnailEdge: Double = 128

    package static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp",
    ]

    package static let readableExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "yaml", "yml", "toml", "csv", "log",
        "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java",
        "kt", "c", "h", "cpp", "hpp", "cs", "php", "sh", "zsh", "bash",
        "sql", "html", "css", "scss", "xml", "plist", "env", "gitignore",
    ]

    package static func kind(forExtension ext: String) -> AttachmentKind {
        imageExtensions.contains(ext.lowercased()) ? .image : .file
    }

    package static func delivery(for ref: AttachmentRef) -> AttachmentDelivery {
        switch ref.kind {
        case .image:
            return .imageDataURL
        case .file:
            return readableExtensions.contains(ext(of: ref)) ? .inlineText : .pathOnly
        }
    }

    package static func mime(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": "image/png"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "heic", "heif": "image/heic"
        case "jpg", "jpeg": "image/jpeg"
        case "tif", "tiff": "image/tiff"
        case "bmp": "image/bmp"
        default:
            readableExtensions.contains(ext.lowercased())
                ? "text/plain" : "application/octet-stream"
        }
    }

    package static func scaledSize(
        width: Double, height: Double, maxEdge: Double = maxImageEdge
    ) -> (width: Double, height: Double) {
        let longest = max(width, height)
        guard longest > maxEdge, longest > 0 else { return (width, height) }
        let scale = maxEdge / longest
        return ((width * scale).rounded(), (height * scale).rounded())
    }

    package static func clipInline(_ text: String) -> String {
        guard text.count > maxInlineChars else { return text }
        return String(text.prefix(maxInlineChars))
            + "\n…(recortado en \(maxInlineChars) caracteres)"
    }

    package static func ext(of ref: AttachmentRef) -> String {
        let fromPath = URL(fileURLWithPath: ref.path).pathExtension
        if !fromPath.isEmpty { return fromPath.lowercased() }
        return URL(fileURLWithPath: ref.name).pathExtension.lowercased()
    }

    /// UUID string is 36 chars plus the hyphen we insert before the name.
    package static func originalName(fromStored fileName: String) -> String {
        fileName.count > 37 ? String(fileName.dropFirst(37)) : fileName
    }

    package static func storedFileName(id: UUID, original: String) -> String {
        "\(id.uuidString)-\(sanitizedFileName(original))"
    }

    /// Direction controls let a name read backwards on screen
    /// ("factura\u{202E}fdp.exe" shows as "factura exe.pdf"): none survive.
    static let bidiControls: Set<UInt32> = [
        0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069,
    ]

    package static func sanitizedFileName(_ name: String) -> String {
        let base = URL(fileURLWithPath: name).lastPathComponent
        let visible = String(String.UnicodeScalarView(
            base.unicodeScalars.filter { !bidiControls.contains($0.value) }))
        let cleaned = visible.replacingOccurrences(of: ":", with: "_")
        return cleaned.isEmpty || cleaned == "/" || cleaned == "." || cleaned == ".."
            ? "file" : cleaned
    }

    package static func isSafeConversationID(_ id: String) -> Bool {
        !id.isEmpty
            && id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            && !id.contains("..")
    }
}

package protocol AttachmentStoring: Sendable {
    func adopt(_ source: URL, conversationId: String) throws -> AttachmentRef
    func adopt(imageData: Data, name: String, conversationId: String) throws -> AttachmentRef
    func restore(path: String) -> AttachmentRef?
    func discard(_ ref: AttachmentRef)
    func payload(for ref: AttachmentRef) -> AttachmentPayload?
    func storedBytes() -> Int
    func purge()
}

package extension AttachmentStoring {
    func storedBytes() -> Int { 0 }
    func purge() {}
}
