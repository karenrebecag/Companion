import CompanionCore
import Foundation
import Observation

public enum FeedbackDelivery: Sendable, Equatable { case opened, openedWithoutCaptures, openedTruncated, failed }

/// How the composed message leaves. The live one opens the user's mail app.
public protocol FeedbackDelivering: Sendable {
    func deliver(_ draft: FeedbackDraft, captures: [URL]) -> FeedbackDelivery
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

extension FeedbackMood {
    /// SF Symbols, not emoji: they follow the text color and scale.
    var symbol: String {
        switch self {
        case .love: "heart"
        case .good: "face.smiling"
        case .meh: "minus.circle"
        case .bad: "hand.thumbsdown"
        }
    }

    var title: String { Localized.string("feedback.mood." + rawValue) }
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

    private let grabber: (any RegionGrabbing)?
    private let delivery: any FeedbackDelivering

    init(grabber: (any RegionGrabbing)?, delivery: any FeedbackDelivering) {
        self.grabber = grabber
        self.delivery = delivery
    }

    var draft: FeedbackDraft { FeedbackDraft(mood: mood, text: text, captureCount: captures.count) }
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
            note = nil
        case .cancelled:
            break
        case .failed:
            note = Localized.string("feedback.note.captureFailed")
        case .needsPermission:
            note = Localized.string("feedback.note.needsScreen")
        }
    }

    func removeCapture(_ url: URL) {
        guard captures.contains(url) else { return }
        captures.removeAll { $0 == url }
        grabber?.discard(url)
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
        if phase != .sent { for url in captures { grabber?.discard(url) } }
        captures = []
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
