import AppKit
import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 16i-2: the grabber never runs the picker without Screen Recording and
// never deletes what it did not write; the island's new words exist in both
// languages; the clip's dropdown behaves like the header's.

private struct FakeScreenPermission: ScreenRecordingChecking {
    let granted: Bool
    let asked = AsyncBox<Bool>()
    func isGranted() -> Bool { granted }
    func request() -> Bool {
        asked.result = .success(true)
        return granted
    }
}

@Test @MainActor func islandAttachWiringTests() async {
    await testNoPermissionAsksInsteadOfCapturing()
    testTheGrabberOnlyDeletesItsOwnCaptures()
    await testTheClipAndDropWordsAreInBothLanguages()
    testTheClipDropdownTogglesLikeTheHeaders()
    testADragCardAnnouncesItself()
    testTheDropReadsOnlyRegularFilesFromDisk()
}

@MainActor func testNoPermissionAsksInsteadOfCapturing() async {
    let permission = FakeScreenPermission(granted: false)
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("grab-test-\(UUID().uuidString)", isDirectory: true)
    let grabber = ScreenRegionGrabber(directory: dir, permission: permission)
    let outcome = await grabber.capture()
    expectEq(outcome, .needsPermission, "sin Grabación de pantalla: no se abre el selector")
    expect(permission.asked.result != nil, "sin permiso: se pide al sistema")
    expect(!FileManager.default.fileExists(atPath: dir.path), "sin permiso: no se crea nada en disco")
}

@MainActor func testTheGrabberOnlyDeletesItsOwnCaptures() {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("grab-own-\(UUID().uuidString)", isDirectory: true)
    let dir = root.appendingPathComponent("captures", isDirectory: true)
    do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let mine = dir.appendingPathComponent("captura-1.png")
        let theirs = root.appendingPathComponent("theirs.png")
        let sneaky = dir.appendingPathComponent("../theirs.png")
        try Data([1]).write(to: mine)
        try Data([1]).write(to: theirs)
        let grabber = ScreenRegionGrabber(directory: dir, permission: FakeScreenPermission(granted: true))
        grabber.discard(theirs)
        grabber.discard(sneaky)
        expect(fm.fileExists(atPath: theirs.path), "discard: un archivo ajeno no se toca, ni con ../")
        grabber.discard(mine)
        expect(!fm.fileExists(atPath: mine.path), "discard: la captura propia se borra")
        try fm.removeItem(at: root)
    } catch {
        expect(false, "discard: preparar el disco no debe fallar (\(error))")
    }
}

@MainActor func testTheClipAndDropWordsAreInBothLanguages() async {
    var keys = IslandAttachItem.allCases.map { "island.attach." + $0.rawValue }
    keys += IslandDropZone.allCases.map { "island.drop." + $0.rawValue }
    keys += ["island.attach.noText", "island.attach.captureFailed", "island.attach.needsScreen",
             "island.drop.title", "island.drop.airDropUnavailable"]
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            for key in keys {
                expect(Localized.string(key) != key, "\(language): \(key) está en el catálogo")
            }
        }
    }
}

@MainActor func testTheClipDropdownTogglesLikeTheHeaders() {
    expectEq(IslandPopoverToggle.next(current: nil, tapped: .attach), .attach, "clip: abre su menú")
    expectEq(IslandPopoverToggle.next(current: .attach, tapped: .attach), nil, "clip: otro clic lo cierra")
    expectEq(IslandPopoverToggle.next(current: .menu, tapped: .attach), .attach, "clip: cambia desde el de «…»")
    expectEq(PortalFrame.next(current: nil, report: CGRect(x: 1, y: 2, width: 3, height: 4),
                              from: .attach, active: .attach),
             CGRect(x: 1, y: 2, width: 3, height: 4), "clip: su menú también toma clics fuera de la forma")
}

@MainActor func testADragCardAnnouncesItself() {
    expect(!IslandCopy.line(.dropZones).isEmpty, "arrastre: la tarjeta tiene nombre para VoiceOver")
}

@MainActor func testTheDropReadsOnlyRegularFilesFromDisk() {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)", isDirectory: true)
    do {
        let folder = root.appendingPathComponent("carpeta", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("nota.txt")
        try Data("hola".utf8).write(to: file)
        let link = root.appendingPathComponent("enlace.txt")
        try fm.createSymbolicLink(at: link, withDestinationURL: file)
        expectEq(IslandDropTarget.regularFiles([folder, file, link]), [file],
                 "soltar: de una carpeta, un archivo y un enlace, solo el archivo")
        try fm.removeItem(at: root)
    } catch {
        expect(false, "soltar: preparar el disco no debe fallar (\(error))")
    }
}
