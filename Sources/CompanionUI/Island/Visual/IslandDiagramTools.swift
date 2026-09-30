import AppKit
import CompanionCore

/// Incredible's diagram tools: copy the image and download the PNG, each
/// with the popup's background or without it, at 2x (16m-5b). The bytes come
/// from the renderer; these only choose a variant and hand it over.
enum IslandDiagramTools {
    /// Nil when the page could not make that PNG: the tool is then unavailable.
    static func pngData(_ image: DiagramImage, background: Bool) -> Data? {
        let data = background ? image.png : image.pngTransparent
        return data.isEmpty ? nil : data
    }

    static func filename(background: Bool) -> String {
        background ? "diagram.png" : "diagram-transparent.png"
    }

    /// PNG for apps that take it, TIFF for those that only take that; both
    /// keep the alpha. An unavailable variant leaves the clipboard alone.
    @discardableResult
    static func copyImage(_ image: DiagramImage, background: Bool, to board: NSPasteboard = .general) -> Bool {
        guard let png = pngData(image, background: background) else { return false }
        board.clearContents()
        board.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { board.setData(tiff, forType: .tiff) }
        return true
    }

    /// `save` is the composition root's save panel. Without a PNG to save the
    /// panel never opens, and that is a failure to tell her about.
    @discardableResult
    static func download(_ image: DiagramImage, background: Bool, save: (Data, String) async -> DiagramSaveResult) async -> DiagramSaveResult {
        guard let png = pngData(image, background: background) else { return .failed }
        return await save(png, filename(background: background))
    }
}

enum IslandDiagramLayout {
    /// The picture at its own size: never shrunk below the popup's 580 (the
    /// container scrolls sideways instead) and never capped in height (the
    /// popup scrolls vertically).
    static func displaySize(_ image: DiagramImage) -> CGSize {
        CGSize(width: image.width, height: image.height)
    }
}
