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

/// Reads a drag and says what it means for the island. One per window; the
/// geometry they share is the single source of truth.
@MainActor
final class IslandDropTarget {
    private let geometry: IslandGeometry
    private var leaving: Task<Void, Never>?

    init(geometry: IslandGeometry) {
        self.geometry = geometry
    }

    /// The drag crosses from one window to the other as the card opens; the
    /// card stays open for a beat so that hand-over does not close it.
    static let exitGrace: Double = 0.15

    static let types: [NSPasteboard.PasteboardType] = [.fileURL]

    func entered(_ info: any NSDraggingInfo, screenPoint: CGPoint, card: CGRect) -> NSDragOperation {
        guard !Self.files(info).isEmpty else { return [] }
        leaving?.cancel()
        geometry.dropping = true
        return updated(screenPoint: screenPoint, card: card)
    }

    func updated(screenPoint: CGPoint, card: CGRect) -> NSDragOperation {
        guard geometry.dropping else { return [] }
        leaving?.cancel()
        geometry.dropZone = IslandDropZone.at(screenPoint, in: card)
        return .copy
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
        geometry.dropping = false
        geometry.dropZone = nil
    }

    func perform(_ info: any NSDraggingInfo) -> Bool {
        let urls = Self.files(info)
        let zone = geometry.dropZone ?? IslandDropZone.fallback
        end()
        guard !urls.isEmpty, let onDrop = geometry.onDrop else { return false }
        onDrop(urls, zone)
        return true
    }

    /// Files only: a dragged link or a text selection is not an attachment.
    static func files(_ info: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let read = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return regularFiles((read as? [URL]) ?? [])
    }

    static func regularFiles(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return IslandDropFilter.keeps(isRegularFile: values.isRegularFile == true,
                                              isSymbolicLink: values.isSymbolicLink == true)
            } catch {
                return false
            }
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
