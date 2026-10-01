import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// 16q-2 visual fixes seen in the snapshot gallery: the comments modal keeps
// its text editor with screenshots attached and its three attach buttons read
// on one line each; the choice card never repeats the question above it.

private final class NoDelivery: FeedbackDelivering, @unchecked Sendable {
    func deliver(_ draft: FeedbackDraft, captures: [URL]) -> FeedbackDelivery { .opened }
}

private final class PickedFiles: FeedbackAttaching, @unchecked Sendable {
    let files: [URL]
    init(_ files: [URL]) { self.files = files }
    @MainActor func chooseImages() async -> [URL] { files }
    @MainActor func pastedImage() -> PastedImage { .empty }
    func isRegularFile(_ url: URL) -> Bool { true }
    func byteSize(of url: URL) -> Int? { 100 }
    func isImage(_ url: URL) -> Bool { true }
    func discard(_ url: URL) {}
}

/// A real, large PNG per name: the bug hid behind what a screenshot does to
/// the layout, so the fixture must be one.
private func screenshots(_ count: Int) throws -> [URL] {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("feedback-visual-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let image = NSImage(size: NSSize(width: 1600, height: 1000), flipped: false) { rect in
        NSColor.systemTeal.setFill()
        rect.fill()
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    return try (0 ..< count).map { index in
        let url = dir.appendingPathComponent("shot\(index).png")
        try png.write(to: url)
        return url
    }
}

@MainActor private func host<V: View>(_ view: V, width: CGFloat) -> (NSWindow, NSView) {
    // The window owns the controller: a view that outlives its controller
    // crashes on the next layout pass.
    let controller = NSHostingController(rootView: AnyView(view))
    // The width is a proposal, not a frame: a fixed frame would let a label
    // overflow instead of wrapping, hiding what the bug is.
    let size = controller.sizeThatFits(in: NSSize(width: width, height: 10_000))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    // Closing would release a window ARC already owns.
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.setContentSize(size)
    controller.view.layoutSubtreeIfNeeded()
    return (window, controller.view)
}

private func textViews(in view: NSView) -> [NSTextView] {
    (view as? NSTextView).map { [$0] } ?? [] + view.subviews.flatMap(textViews)
}

@MainActor private func attachedModel(_ count: Int) async throws -> FeedbackModel {
    let model = FeedbackModel(
        grabber: nil, delivery: NoDelivery(), attachments: PickedFiles(try screenshots(count)))
    await model.addFiles()
    return model
}

// MARK: - Bug 1

@Test @MainActor func theTextEditorStaysVisibleWithThreeScreenshotsAttached() async throws {
    let empty = FeedbackModel(grabber: nil, delivery: NoDelivery())
    let full = try await attachedModel(3)
    expectEq(full.captures.count, FeedbackDraft.maxCaptures, "16q-2: tres capturas adjuntas")

    let (bareWindow, bare) = host(FeedbackModal(model: empty, onClose: {}), width: FeedbackMetrics.width)
    let (fullWindow, filled) = host(FeedbackModal(model: full, onClose: {}), width: FeedbackMetrics.width)
    defer { bareWindow.close(); fullWindow.close() }

    let bareEditors = textViews(in: bare), fullEditors = textViews(in: filled)
    expectEq(bareEditors.count, 1, "16q-2: sin capturas hay un editor")
    expectEq(fullEditors.count, 1, "16q-2: con capturas el editor sigue ahi, no lo reemplaza la imagen")
    let height = fullEditors.first?.enclosingScrollView?.frame.height ?? 0
    expectEq(height, Container.hero, "16q-2: y conserva su alto medido (\(Container.hero))")

    // At three the attach buttons leave (the cap), so the strip is compared
    // where both are on screen.
    let two = try await attachedModel(2)
    let (twoWindow, some) = host(FeedbackModal(model: two, onClose: {}), width: FeedbackMetrics.width)
    defer { twoWindow.close() }
    expect(some.frame.height >= bare.frame.height + Space.x10,
           "16q-2: las miniaturas suman una tira debajo del editor (\(some.frame.height) vs \(bare.frame.height))")
}

@Test @MainActor func theThreeAttachButtonsNeverWrapAWordInsideAButton() async {
    let inner = FeedbackMetrics.width - 2 * FeedbackMetrics.padding
    // Spanish is the longer catalog, and the one the gallery showed wrapping.
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            let (chipWindow, chip) = host(
                FeedbackAttachChip(key: "feedback.capture.file", symbol: "photo", action: {}), width: 2000)
            let (rowWindow, row) = host(
                FeedbackAttachRow(onRegion: {}, onFile: {}, onPaste: {}), width: inner)
            defer { chipWindow.close(); rowWindow.close() }
            let lineHeight = chip.frame.height
            let rows = (row.frame.height + Space.x2) / (lineHeight + Space.x2)
            expect(abs(rows - rows.rounded()) < 0.1 && rows >= 1,
                   "16q-2 (\(language)): un numero entero de botones de una linea, no palabras partidas (\(rows) filas de \(lineHeight))")
            expect(row.frame.width <= inner + 0.5, "16q-2 (\(language)): cabe en el ancho medido del modal")
        }
    }
}

// MARK: - Bug 2

private func fence(_ question: String) -> String {
    "```companion:choice\n{\"question\":\"\(question)\",\"options\":[\"Rapido\",\"Completo\"]}\n```"
}

@Test @MainActor func aReplyThatRepeatsTheQuestionShowsItOnlyOnTheCard() {
    let question = "¿Cómo prefieres que lo prepare?"
    for said in [question, "  \(question)\n", "¿Cómo   prefieres\tque lo   prepare?"] {
        let ask = ChatMessage(role: .assistant, isStatus: false, text: said + "\n\n" + fence(question))
        expectEq(IslandView.replyText(for: ask), "", "16q-2: el texto repetido se omite - \(said.debugDescription)")
    }
}

@Test @MainActor func aReplyThatDiffersFromTheQuestionKeepsBoth() {
    let ask = ChatMessage(
        role: .assistant, isStatus: false,
        text: "Tengo dos formatos.\n\n" + fence("¿Cómo prefieres que lo prepare?"))
    expectEq(IslandView.replyText(for: ask), "Tengo dos formatos.", "16q-2: si difiere, ambos se quedan")
    let plain = ChatMessage(role: .assistant, isStatus: false, text: "Listo.")
    expectEq(IslandView.replyText(for: plain), "Listo.", "16q-2: sin tarjeta, el texto no cambia")
    let almost = ChatMessage(
        role: .assistant, isStatus: false,
        text: "¿Cómo prefieres que lo prepare hoy?\n\n" + fence("¿Cómo prefieres que lo prepare?"))
    expectEq(IslandView.replyText(for: almost), "¿Cómo prefieres que lo prepare hoy?", "16q-2: casi igual no es igual")
}
