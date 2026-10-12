import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing

// 16h-3: the receipt card. The gallery is for looking at (opt-in, reported
// as skipped otherwise, never a green no-op); the content tests below are
// what the suite actually checks.

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func receiptSnapshots() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let one = chat()
    one.session.send(.receipt(ActionReceipt(lines: ["Abrí Safari."])!))
    let many = chat()
    many.session.send(.receipt(ActionReceipt(lines: [
        "Abrí Notas.", "Escribí el texto.", "Abrí https://atomchat.io/blog/como-migrar-un-sitio-de-wordpress-a-webflow-sin-perder-seo.",
        "Pulsé Cmd+S.",
    ])!))
    try await Localized.scoped(to: .es) {
        for (name, model) in [("receipt-one", one), ("receipt-four", many)] {
            try await saveLive(island(model), scheme: .dark, size: CGSize(width: 640, height: 420), to: out, name)
        }
    }
}

// MARK: - Content

private let openedLine = ReceiptLine(text: "Abrí Safari.", verified: false)
private let typedLine = ReceiptLine(text: "Escribí el texto.", verified: true)

@Test @MainActor func testEachReceiptLineIsLabelledDoneOrDoneAndVerifiedByItsOwnProof() {
    let receipt = ActionReceipt(entries: [openedLine, typedLine])!
    let expected: [AppLanguage: [String]] = [
        .es: ["Hecho", "Hecho y comprobado"], .en: ["Done", "Done and verified"],
    ]
    for (language, labels) in expected {
        expectEq(receipt.entries.map { IslandReceipt.checkLabel($0, language: language) }, labels,
                 "recibo (\(language)): cada línea dice hecho o comprobado según su propia prueba")
    }
}

@Test @MainActor func testTheAnnouncementReadsTheTitleAndAllFourLinesInOrder() {
    let lines = ["Abrí Notas.", "Escribí el texto.", "Abrí atomchat.io/blog.", "Pulsé Cmd+S."]
    let receipt = ActionReceipt(lines: lines)!
    expectEq(receipt.lines.count, ActionReceipt.maxLines, "anuncio: el recibo lleva cuatro líneas")
    expectEq(IslandReceipt.announcement(receipt, language: .es),
             "Hecho. Abrí Notas.. Escribí el texto.. Abrí atomchat.io/blog.. Pulsé Cmd+S.",
             "anuncio (es): título y las cuatro líneas, en orden")
    expectEq(IslandReceipt.announcement(receipt, language: .en).hasPrefix("Done. Abrí Notas."), true,
             "anuncio (en): el título va en el idioma pedido")
}

@Test @MainActor func testALongUrlIsCutOnTheModelBeforeItReachesTheCard() {
    let host = "https://atomchat.io/" + String(repeating: "blog/", count: 60)
    let long = ActionReceipt(lines: ["Abrí " + host + "."])!
    let cut = long.lines[0]
    expect(cut.unicodeScalars.count <= ActionReceipt.maxLineLength + 1 && cut.hasSuffix("…"),
           "url larga: el modelo la acota con el corte visible — \(cut.count) caracteres")
}
