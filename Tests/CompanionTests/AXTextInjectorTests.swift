import CompanionCore
@testable import CompanionServices
import AppKit
import Foundation
import Testing

// Wave 12e. Lo comprobable del inyector sin otra app delante: el
// portapapeles del usuario vuelve como estaba, y no se pisa lo que alguien
// escribió mientras tanto (revisión de seguridad 2026-09-06).

@Test @MainActor func axTextInjectorTests() {
    testThePasteboardComesBack()
    testAConcurrentCopyWins()
    testAnEmptyPasteboardComesBackEmpty()
    testTheOwnBundleIDIsRequired()
}

private func board(_ label: String) -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("companion-test-\(label)-\(UUID().uuidString)"))
}

/// Todos los tipos, no solo el texto: un dictado no se come la imagen que
/// la usuaria iba a pegar.
@MainActor func testThePasteboardComesBack() {
    let pb = board("restore")
    let item = NSPasteboardItem()
    item.setString("lo que había", forType: .string)
    item.setData(Data([0x89, 0x50]), forType: .png)
    pb.clearContents()
    pb.writeObjects([item])

    let saved = AXTextInjector.snapshot(pb)
    pb.clearContents()
    pb.setString("lo dictado", forType: .string)
    expectEq(pb.string(forType: .string), "lo dictado", "portapapeles: el dictado pasa por ahí")

    expect(AXTextInjector.restore(saved, to: pb, ifUnchangedFrom: pb.changeCount),
           "portapapeles: nadie más lo tocó, se restaura")
    expectEq(pb.string(forType: .string), "lo que había", "portapapeles: vuelve el texto")
    expectEq(pb.data(forType: .png), Data([0x89, 0x50]), "portapapeles: y la imagen")
}

/// Si alguien copia durante los 300 ms, lo suyo manda: restaurar a ciegas
/// le borraría lo que acaba de copiar.
@MainActor func testAConcurrentCopyWins() {
    let pb = board("collision")
    pb.clearContents()
    pb.setString("lo que había", forType: .string)
    let saved = AXTextInjector.snapshot(pb)
    pb.clearContents()
    pb.setString("lo dictado", forType: .string)
    let mine = pb.changeCount

    pb.clearContents()
    pb.setString("lo que copió la usuaria", forType: .string)

    expect(!AXTextInjector.restore(saved, to: pb, ifUnchangedFrom: mine),
           "portapapeles: con una copia de por medio no se restaura")
    expectEq(pb.string(forType: .string), "lo que copió la usuaria",
             "portapapeles: lo suyo se queda")
}

@MainActor func testAnEmptyPasteboardComesBackEmpty() {
    let pb = board("empty")
    pb.clearContents()
    let saved = AXTextInjector.snapshot(pb)
    pb.clearContents()
    pb.setString("lo dictado", forType: .string)
    expect(AXTextInjector.restore(saved, to: pb, ifUnchangedFrom: pb.changeCount),
           "portapapeles: vacío también se restaura")
    expect(pb.string(forType: .string) == nil, "portapapeles: vuelve vacío, sin el dictado")
}

/// Sin identificador propio no hay forma de excluirse: el inyector no
/// arranca en vez de arriesgarse a escribir en la ventana de Companion.
@MainActor func testTheOwnBundleIDIsRequired() {
    expect(AXTextInjector(selfBundleID: "com.karen.companion.next") != nil,
           "identidad: con bundle id se construye")
    expect(AXTextInjector(selfBundleID: "") == nil, "identidad: sin bundle id no")
    expect(AXTextInjector(selfBundleID: "   ") == nil, "identidad: ni con espacios")
}
