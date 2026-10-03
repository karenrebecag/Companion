import CompanionCore
import Foundation
import Observation

package enum FeedbackDelivery: Sendable, Equatable { case opened, openedWithoutCaptures, openedTruncated, failed }

/// How the composed message leaves. The live one opens the user's mail app.
package protocol FeedbackDelivering: Sendable {
    func deliver(_ draft: FeedbackDraft, captures: [URL]) -> FeedbackDelivery
}

/// What reading the clipboard's image came to: nothing there, too big to
/// keep (nothing written), a write that failed, or the file.
package enum PastedImage: Sendable, Equatable {
    case empty, tooBig, failed, image(URL)
}

/// Where the screenshots that are not region grabs come from (16q-2): a file
/// picker and the clipboard. A port so the model is tested without AppKit.
package protocol FeedbackAttaching: Sendable {
    /// The images she chose in the picker (empty when she cancelled).
    @MainActor func chooseImages() async -> [URL]
    /// The clipboard's image written to a private temporary file.
    @MainActor func pastedImage() -> PastedImage
    /// A regular file, not a symlink, folder or package.
    func isRegularFile(_ url: URL) -> Bool
    func byteSize(of url: URL) -> Int?
    func isImage(_ url: URL) -> Bool
    /// Removes a file `pastedImage()` wrote. Never called for a chosen file.
    func discard(_ url: URL)
}

/// Incredible's comments modal (docs/research/incredible-isla-componentes.md
/// §5): 480 wide, padding 32, radius 28. Pinned in Feedback16m7Tests.
enum FeedbackMetrics {
    static let width: CGFloat = 480
    static let padding: CGFloat = 32
    static let radius: CGFloat = 28
}

enum FeedbackCopy {
    static func counter(remaining: Int) -> (text: String, over: Bool) {
        let key = remaining < 0 ? "feedback.counter.over" : "feedback.counter"
        return (String(format: Localized.string(key), abs(remaining)), remaining < 0)
    }
}

/// An SF Symbol where one exists, a drawn face where SF has none; never
/// emoji, so every mood follows the text color and size.
nonisolated enum MoodGlyph: Hashable {
    case symbol(String)
    case face(MoodFace)
}

extension FeedbackMood {
    /// Incredible's feedback row: angry, sad and flat faces, a smile, a heart.
    var glyph: MoodGlyph {
        switch self {
        case .upset: .face(.angry)
        case .bad: .face(.sad)
        case .meh: .face(.meh)
        case .good: .symbol("face.smiling")
        case .love: .symbol("heart")
        }
    }

    var title: String { Localized.string("feedback.mood." + rawValue) }
}

extension FeedbackTopic {
    var title: String { Localized.string("feedback.topic." + rawValue) }
}

/// The modal's state. A capture is taken only when `addCapture()` is called,
/// which only a button does; opening the modal grabs nothing.
@Observable
@MainActor
final class FeedbackModel {
    enum Phase: Equatable { case composing, sent, closed }

    var mood: FeedbackMood?
    private(set) var text = ""
    private(set) var captures: [URL] = []
    private(set) var note: String?
    private(set) var phase = Phase.composing
    private var isCapturing = false
    /// Who wrote each capture's file, so only that owner ever deletes it: a
    /// file she chose from her disk is hers and is never touched.
    private enum Origin { case region, pasted, chosen }
    private var origins: [URL: Origin] = [:]

    private(set) var topics: [FeedbackTopic] = []

    private let grabber: (any RegionGrabbing)?
    private let delivery: any FeedbackDelivering
    private let attachments: (any FeedbackAttaching)?

    init(grabber: (any RegionGrabbing)?, delivery: any FeedbackDelivering,
         attachments: (any FeedbackAttaching)? = nil) {
        self.grabber = grabber
        self.delivery = delivery
        self.attachments = attachments
    }

    var draft: FeedbackDraft {
        FeedbackDraft(mood: mood, text: text, captureCount: captures.count, topics: topics)
    }

    func toggleTopic(_ topic: FeedbackTopic) {
        if topics.contains(topic) { topics.removeAll { $0 == topic } } else { topics.append(topic) }
        topics = FeedbackTopic.allCases.filter(topics.contains)
    }
    var canSend: Bool { phase == .composing && draft.canSend }

    func setText(_ value: String) {
        text = FeedbackDraft.clipped(value)
    }

    func addCapture() async {
        // A second press while the picker is up would open a second one.
        guard !isCapturing else { return }
        guard captures.count < FeedbackDraft.maxCaptures else {
            note = Localized.string("feedback.note.limit")
            return
        }
        guard let grabber else {
            note = Localized.string("feedback.note.noGrabber")
            return
        }
        isCapturing = true
        defer { isCapturing = false }
        switch await grabber.capture() {
        case .captured(let url):
            // The modal may have closed, or filled up, while the picker was up.
            guard phase == .composing, captures.count < FeedbackDraft.maxCaptures else {
                grabber.discard(url)
                return
            }
            captures.append(url)
            origins[url] = .region
            note = nil
        case .cancelled:
            break
        case .failed:
            note = Localized.string("feedback.note.captureFailed")
        case .needsPermission:
            note = Localized.string("feedback.note.needsScreen")
        }
    }

    /// The picker: images from her disk, up to the room left. Guarded like
    /// the region capture: a second press while it is up opens no second one.
    func addFiles() async {
        guard !isCapturing else { return }
        guard captures.count < FeedbackDraft.maxCaptures else {
            note = Localized.string("feedback.note.limit")
            return
        }
        guard let attachments else {
            note = Localized.string("feedback.note.noFiles")
            return
        }
        isCapturing = true
        defer { isCapturing = false }
        let chosen = await attachments.chooseImages()
        // The modal may have closed while the picker was up.
        guard phase == .composing else { return }
        var skipped = false
        var lastRefusal: String?
        for url in chosen {
            if captures.contains(url) { continue }
            guard captures.count < FeedbackDraft.maxCaptures else { skipped = true; break }
            if let why = refusal(for: url, using: attachments) { lastRefusal = why; continue }
            captures.append(url)
            origins[url] = .chosen
        }
        note = lastRefusal ?? (skipped ? Localized.string("feedback.note.limit") : nil)
    }

    /// The clipboard's image, if it holds one. Full: the clipboard is not
    /// even read, so nothing is written to disk for a screenshot that cannot
    /// be kept.
    func addPasted() {
        guard phase == .composing else { return }
        guard captures.count < FeedbackDraft.maxCaptures else {
            note = Localized.string("feedback.note.limit")
            return
        }
        guard let attachments else {
            note = Localized.string("feedback.note.noFiles")
            return
        }
        let url: URL
        switch attachments.pastedImage() {
        case .image(let written): url = written
        case .empty:
            note = Localized.string("feedback.note.noPaste")
            return
        case .failed:
            note = Localized.string("feedback.note.pasteFailed")
            return
        case .tooBig:
            note = Localized.string("feedback.note.tooBig")
            return
        }
        if let why = refusal(for: url, using: attachments) {
            attachments.discard(url)
            note = why
            return
        }
        captures.append(url)
        origins[url] = .pasted
        note = nil
    }

    private func refusal(for url: URL, using attachments: any FeedbackAttaching) -> String? {
        guard attachments.isRegularFile(url) else { return Localized.string("feedback.note.unreadable") }
        guard attachments.isImage(url) else { return Localized.string("feedback.note.notImage") }
        guard let size = attachments.byteSize(of: url) else { return Localized.string("feedback.note.unreadable") }
        guard size <= FeedbackDraft.maxCaptureBytes else { return Localized.string("feedback.note.tooBig") }
        return nil
    }

    func removeCapture(_ url: URL) {
        guard captures.contains(url) else { return }
        captures.removeAll { $0 == url }
        discard(url)
    }

    private func discard(_ url: URL) {
        switch origins.removeValue(forKey: url) {
        case .region: grabber?.discard(url)
        case .pasted: attachments?.discard(url)
        case .chosen, nil: break
        }
    }

    func send() {
        guard canSend else { return }
        switch delivery.deliver(draft, captures: captures) {
        case .opened:
            note = nil
            phase = .sent
        case .openedTruncated:
            note = Localized.string("feedback.note.truncated")
            phase = .sent
        case .openedWithoutCaptures:
            note = Localized.string("feedback.note.noAttach")
            phase = .sent
        case .failed:
            note = Localized.string("feedback.note.deliveryFailed")
        }
    }

    /// Closing without sending leaves nothing behind. After a send the files
    /// stay: the mail app may still be reading them.
    func cancel() {
        if phase != .sent { for url in captures { discard(url) } }
        captures = []
        origins = [:]
        phase = .closed
    }
}

/// Where a message goes, decided apart from the system calls so every branch
/// can be exercised: the share service when there are screenshots or the text
/// does not fit a mail link; otherwise (or when there is no service) the mail
/// link, cut and reported when it has to be.
struct FeedbackDeliverer {
    var share: (_ subject: String, _ items: [Any]) -> Bool
    var open: (URL) -> Bool

    func deliver(_ draft: FeedbackDraft, captures: [URL], subject: String, language: AppLanguage) -> FeedbackDelivery {
        let link = draft.mailto(subject: subject, language: language)
        if !captures.isEmpty || link?.truncated != false {
            if share(subject, [draft.body(language: language)] + captures) { return .opened }
        }
        guard let link, open(link.url) else { return .failed }
        if !captures.isEmpty { return .openedWithoutCaptures }
        return link.truncated ? .openedTruncated : .opened
    }
}

/// A request to open the modal that arrives before the main window's view
/// exists is kept here and read when it appears; a notification alone would
/// be lost.
@MainActor
enum FeedbackRequest {
    private static var pending = false
    static func raise() { pending = true }
    static func consume() -> Bool {
        defer { pending = false }
        return pending
    }
    static func clear() { pending = false }
}
