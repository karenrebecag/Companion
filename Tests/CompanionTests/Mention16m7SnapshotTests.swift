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

@MainActor private func write<V: View>(_ view: V, _ name: String, to dir: URL) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { expect(false, "16m-7 snapshot: \(name) no rindió"); return }
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

    let feedback = FeedbackModel(grabber: NoGrab(), delivery: NoMail())
    feedback.mood = .good
    feedback.setText("La isla se pliega cuando escribo una @ y aparece el diálogo de contactos.")
    for scheme in [ColorScheme.dark, .light] {
        try write(FeedbackModal(model: feedback, onClose: {}).padding(20).background(Color.gray)
            .environment(\.colorScheme, scheme), "feedback-\(scheme == .dark ? "dark" : "light")", to: out)
    }
}
