import AppKit
import CompanionCore
import SwiftUI

// Wave 16i-2 (spec 16i §4, §11): a file dragged onto the notch opens it with
// somewhere to drop. The island passes the pointer through everywhere but its
// shape, and a window that ignores the mouse also ignores drags; the pointer
// monitor does not reliably run while another app owns the drag. So a second,
// drag-only window sits under the island at the shape's rect: when the island
// takes the pointer it gets the drag, otherwise this one does. Both answer
// through the same target, so the zones behave the same either way.

/// The highlight a drag lights, apart from AppKit so enter, exit and drop
/// can be tested without a dragging session.
struct IslandDropHighlight: Equatable {
    private(set) var dropping = false
    private(set) var zone: IslandDropZone?

    enum Entry: Equatable {
        case began, continued, ignored
    }

    /// A drag with no files lights nothing and leaves an active drag as it
    /// was. Only `.began` is a new drag, so it is the one announced.
    mutating func enter(hasFiles: Bool) -> Entry {
        guard hasFiles else { return .ignored }
        let entry: Entry = dropping ? .continued : .began
        dropping = true
        return entry
    }

    mutating func move(to zone: IslandDropZone?) -> Bool {
        guard dropping else { return false }
        self.zone = zone
        return true
    }

    mutating func end() {
        dropping = false
        zone = nil
    }

    /// Where a drop lands, then the highlight is gone. Dropped before the
    /// card opened there is no zone yet and asking is the default.
    mutating func drop() -> IslandDropZone {
        let landed = zone ?? IslandDropZone.fallback
        end()
        return landed
    }
}

/// Reads a drag and says what it means for the island. One per window; the
/// geometry they share is the single source of truth.
@MainActor
final class IslandDropTarget {
    private let geometry: IslandGeometry
    private var leaving: Task<Void, Never>?
    private var highlight = IslandDropHighlight()

    init(geometry: IslandGeometry) {
        self.geometry = geometry
    }

    /// The drag crosses from one window to the other as the card opens; the
    /// card stays open for a beat so that hand-over does not close it.
    static let exitGrace: Double = 0.15

    static let types: [NSPasteboard.PasteboardType] = [.fileURL]

    func entered(_ info: any NSDraggingInfo, screenPoint: CGPoint, card: CGRect) -> NSDragOperation {
        let entry = highlight.enter(hasFiles: !Self.files(info).isEmpty)
        guard entry != .ignored else { return [] }
        leaving?.cancel()
        if entry == .began { announce() }
        return updated(screenPoint: screenPoint, card: card)
    }

    func updated(screenPoint: CGPoint, card: CGRect) -> NSDragOperation {
        guard highlight.move(to: IslandDropZone.at(screenPoint, in: card)) else { return [] }
        leaving?.cancel()
        sync()
        return .copy
    }

    /// The zones are painted, not focused, so VoiceOver would not say that
    /// the notch now takes the file.
    private func announce() {
        sync()
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: Localized.string("island.drop.a11y"),
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func sync() {
        geometry.dropping = highlight.dropping
        geometry.dropZone = highlight.zone
    }

    func exited() {
        leaving?.cancel()
        leaving = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(Self.exitGrace)) } catch { return }
            self?.end()
        }
    }

    private func end() {
        leaving?.cancel()
        highlight.end()
        sync()
    }

    func perform(_ info: any NSDraggingInfo) -> Bool {
        let urls = Self.files(info)
        let zone = highlight.drop()
        end()
        guard !urls.isEmpty, let onDrop = geometry.onDrop else { return false }
        onDrop(urls, zone)
        return true
    }

    /// File URLs only: a dragged web link or a text selection is not an
    /// attachment. Folders and links pass here and are refused where they
    /// are staged, so the refusal is shown rather than swallowed.
    static func files(_ info: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let read = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (read as? [URL]) ?? []
    }

    /// Why a dropped URL is or is not an attachment: a read that throws
    /// (vanished, no permission) is not a folder and must not be called one.
    static func verdict(_ url: URL) -> IslandDropVerdict {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return IslandDropFilter.keeps(isRegularFile: values.isRegularFile == true,
                                          isSymbolicLink: values.isSymbolicLink == true)
                ? .ok : .notFile
        } catch {
            return .unreadable
        }
    }

    static func sort(_ urls: [URL]) -> (files: [URL], refused: [(url: URL, verdict: IslandDropVerdict)]) {
        var files: [URL] = []
        var refused: [(url: URL, verdict: IslandDropVerdict)] = []
        for url in urls {
            let verdict = verdict(url)
            if verdict == .ok { files.append(url) } else { refused.append((url, verdict)) }
        }
        return (files, refused)
    }

    static func regularFiles(_ urls: [URL]) -> [URL] { sort(urls).files }
}

enum IslandDropVerdict: Equatable {
    case ok, notFile, unreadable

    /// The honest words for a refusal; nil when nothing was refused.
    var refusal: String? {
        switch self {
        case .ok: nil
        case .notFile: Localized.string("island.attach.notFile")
        case .unreadable: ChatCopy.attachFailed(.unreadable)
        }
    }
}

/// The island's own view, so a drag reaches it when it holds the pointer.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var dropTarget: IslandDropTarget?
    /// The shape in screen coordinates, for the zone under the pointer.
    var card: () -> CGRect = { .zero }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropTarget?.entered(sender, screenPoint: screenPoint(sender), card: card()) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropTarget?.updated(screenPoint: screenPoint(sender), card: card()) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropTarget?.exited()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropTarget?.perform(sender) ?? false
    }

    private func screenPoint(_ info: any NSDraggingInfo) -> CGPoint {
        window?.convertPoint(toScreen: info.draggingLocation) ?? .zero
    }
}

/// The drag-only window under the island. Clear, no content; it never
/// becomes key and is ordered out when the island is hidden.
final class IslandDropCatcher: NSPanel {
    private let catcherView: IslandDropCatcherView

    init(target: IslandDropTarget) {
        catcherView = IslandDropCatcherView(target: target)
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Companion's own screenshots must not see it.
        sharingType = .none
        contentView = catcherView
        catcherView.registerForDraggedTypes(IslandDropTarget.types)
    }

    /// Follows the island's shape; nothing to catch when there is no shape.
    func follow(_ rect: CGRect, below island: NSWindow) {
        guard rect.width > 0, rect.height > 0, island.isVisible else {
            orderOut(nil)
            return
        }
        setFrame(rect, display: false)
        catcherView.card = rect
        order(.below, relativeTo: island.windowNumber)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class IslandDropCatcherView: NSView {
    private let target: IslandDropTarget
    var card: CGRect = .zero

    init(target: IslandDropTarget) {
        self.target = target
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        target.entered(sender, screenPoint: screenPoint(sender), card: card)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        target.updated(screenPoint: screenPoint(sender), card: card)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        target.exited()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        target.perform(sender)
    }

    private func screenPoint(_ info: any NSDraggingInfo) -> CGPoint {
        window?.convertPoint(toScreen: info.draggingLocation) ?? .zero
    }
}
