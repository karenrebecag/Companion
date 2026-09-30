import AppKit
import CompanionCore
import Foundation
import os
import UniformTypeIdentifiers

package extension Notification.Name {
    /// The island's "Send feedback" entry: the modal lives in the main window.
    static let companionOpenFeedback = Notification.Name("companion.openFeedback")
}

/// The existing destination, unchanged: a new message in the user's own mail
/// app. With screenshots the system share service is the only way to attach
/// files; if it is not there the text still goes by `mailto:` and the model
/// says the screenshots stayed behind.
struct SystemFeedbackDelivery: FeedbackDelivering {
    func deliver(_ draft: FeedbackDraft, captures: [URL]) -> FeedbackDelivery {
        FeedbackDeliverer(
            share: { subject, items in
                guard let service = NSSharingService(named: .composeEmail) else { return false }
                service.subject = subject
                guard service.canPerform(withItems: items) else { return false }
                service.perform(withItems: items)
                return true
            },
            open: { NSWorkspace.shared.open($0) })
            .deliver(draft, captures: captures, subject: Localized.string("island.feedback.subject"),
                     language: Localized.language())
    }
}

/// The file picker and the clipboard behind the modal (16q-2). A pasted
/// bitmap is written to a private folder of ours and is the only thing this
/// ever deletes; a file she chose stays where it is.
struct SystemFeedbackAttachments: FeedbackAttaching {
    // UI does not reach Services' Log; the message never names a path.
    private static let log = Logger(subsystem: "com.karen.companion", category: "feedback")

    /// HACK: leftovers of a pasted image (after a send, the mail app may still
    /// be reading it) stay in the temp folder until macOS clears it. Purge at
    /// launch, like the region captures, once feedback screenshots are seen
    /// piling up there or a review flags the retention.
    private let directory: URL

    init(directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-feedback-paste", isDirectory: true)) {
        self.directory = directory.standardizedFileURL
    }

    static func fits(pngByteCount: Int) -> Bool { pngByteCount <= FeedbackDraft.maxCaptureBytes }

    /// Private even when the folder was already there (a 0755 leftover).
    func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    @MainActor func chooseImages() async -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.urls : [])
            }
        }
    }

    @MainActor func pastedImage() -> PastedImage {
        let board = NSPasteboard.general
        // HACK: TIFF to PNG runs on the main thread. A screenshot-sized image
        // is a few tens of ms; move it off the main actor if a paste of a
        // very large image is ever seen to stall the modal.
        guard let image = NSImage(pasteboard: board),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return .empty }
        // Over the cap nothing is written: no file for a screenshot that
        // cannot be kept.
        guard Self.fits(pngByteCount: png.count) else { return .tooBig }
        do {
            try prepareDirectory()
            let url = directory.appendingPathComponent("\(UUID().uuidString).png")
            try png.write(to: url, options: .atomic)
            return .image(url)
        } catch {
            Self.log.error("could not write the pasted image")
            return .failed
        }
    }

    func isRegularFile(_ url: URL) -> Bool { RegularFile.isRegular(url) }

    func byteSize(of url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    func isImage(_ url: URL) -> Bool {
        // Asked of the system, not read off the extension.
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) == true
    }

    func discard(_ url: URL) {
        let target = url.standardizedFileURL
        guard target.path.hasPrefix(directory.path + "/") else { return }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            Self.log.error("could not remove a pasted image")
        }
    }
}
