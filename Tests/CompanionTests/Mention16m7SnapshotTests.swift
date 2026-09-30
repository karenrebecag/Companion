import AppKit
import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 16m-7: gallery of the selector (list, channels, permission-less) and
// the comments modal. Only with COMPANION_SNAPSHOTS.

private struct Book: ContactsProviding {
    func access() -> ContactsAccess { .granted }
    func requestAccess() async -> Bool { true }
    func search(_ query: String, limit: Int) async -> [MentionCandidate] {
        ["Ana García", "Ana Paula Ríos", "Andrés Molina"].compactMap { MentionCandidate(id: $0, kind: .contact, name: $0) }
    }
    func channels(ofContact id: String) async -> [MentionChannel] {
        [MentionChannel(kind: .email, label: "work", value: "ana@example.com")!,
         MentionChannel(kind: .phone, label: "mobile", value: "+52 55 0000 0000")!]
    }
}

private final class NoGrab: RegionGrabbing, @unchecked Sendable {
    func capture() async -> RegionGrab { .cancelled }
    func recognizeText(at url: URL) async -> String? { nil }
    func discard(_ url: URL) {}
}

private struct NoMail: FeedbackDelivering {
    func deliver(_ draft: FeedbackDraft, captures: [URL]) -> FeedbackDelivery { .opened }
}

private struct SnapshotFiles: FeedbackAttaching {
    let files: [URL]
    init(_ files: [URL]) { self.files = files }
    @MainActor func chooseImages() async -> [URL] { files }
    @MainActor func pastedImage() -> PastedImage { .empty }
    func isRegularFile(_ url: URL) -> Bool { true }
    func byteSize(of url: URL) -> Int? { 100 }
    func isImage(_ url: URL) -> Bool { true }
    func discard(_ url: URL) {}
}

@MainActor private func write<V: View>(_ view: V, _ name: String, to dir: URL) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { expect(false, "16m-7 snapshot: \(name) no rindió"); return }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}

/// ImageRenderer paints a placeholder (yellow with a prohibition sign) for
/// AppKit-backed controls such as the modal's text editor, so a view that has
/// one is drawn from a real hosting view instead.
@MainActor private func writeHosted<V: View>(_ view: V, _ name: String, to dir: URL) throws {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    // Closing would release a window ARC already owns.
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    defer { window.close() }
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
          hosting.bounds.width > 0
    else { expect(false, "16m-7 snapshot: \(name) no rindio"); return }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:])
    else { expect(false, "16m-7 snapshot: \(name) no codifico"); return }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}

@Test @MainActor func mentionSnapshots() async throws {
    guard let path = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    func selector(_ contacts: (any ContactsProviding)?, draft: String, right: Bool = false) async -> MentionSelectorModel {
        let apps = ["Slack", "Notion"].compactMap { MentionCandidate(id: $0.lowercased(), kind: .app, name: $0) }
        let files = [MentionCandidate(id: "/Users/k/Documents/Plan Anual.pdf", kind: .file, name: "Plan Anual.pdf", detail: "Documents")!]
        let model = MentionSelectorModel(sources: MentionSources(contacts: contacts, connectedApps: { apps }, recentFiles: { files }))
        model.update(draft: draft)
        await pumpUntil("snapshot list") { model.rows.count >= 2 }
        await settle(0.1)
        if right { _ = model.press(.right); await settle(0.1) }
        return model
    }
    let full = await selector(Book(), draft: "escríbele a @an")
    let channels = await selector(Book(), draft: "escríbele a @ana", right: true)
    let bare = await selector(nil, draft: "@")
    for (name, model) in [("list", full), ("channels", channels), ("nopermission", bare)] {
        try write(MentionSelectorView(model: model).frame(width: 440).padding(20).background(Color.black)
            .environment(\.colorScheme, .dark), "mention-\(name)", to: out)
    }

    let shots = try [0, 1].map { index -> URL in
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-snapshot-\(index).png")
        let image = NSImage(size: NSSize(width: 1600, height: 1000), flipped: false) { rect in
            (index == 0 ? NSColor.systemTeal : NSColor.systemIndigo).setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
        return url
    }
    let feedback = FeedbackModel(grabber: NoGrab(), delivery: NoMail(), attachments: SnapshotFiles(shots))
    await feedback.addFiles()
    feedback.mood = .good
    feedback.setText("La isla se pliega cuando escribo una @ y aparece el diálogo de contactos.")
    for scheme in [ColorScheme.dark, .light] {
        try writeHosted(FeedbackModal(model: feedback, onClose: {}).padding(20).background(Color.gray)
            .environment(\.colorScheme, scheme), "feedback-\(scheme == .dark ? "dark" : "light")", to: out)
    }
}
