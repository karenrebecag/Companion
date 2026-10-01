import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 16i-2 (spec 16i §2, §4, §11): the clip opens Incredible's three ways
// in, a region capture becomes an attachment or text in the field, and a
// file dragged onto the notch opens it with somewhere to drop.

@Test func islandAttachTests() {
    testTheClipOffersIncrediblesThreeWaysIn()
    testTheRegionPickerIsTheSystemsOwnAndSilent()
    testEscapeInThePickerIsACancelNotAFailure()
    testRecognizedTextReadsTopToBottomLeftToRight()
    testNoTextIsNothingToPaste()
    testCapturedTextJoinsTheDraftWithoutGluingWords()
    testCapturedTextIsClippedLikeAnyInlineText()
    testTheDropZonesSplitTheOpenCard()
    testADragOverTheNotchOpensTheDropCard()
    testADragNeverCoversAQuestionOrWork()
    testAStagedAttachmentKeepsTheFieldOpen()
    testOnlyRegularFilesAreDropped()
    testTheCatcherOnlyCoversTheHardwareNotchOrADrag()
}

func testTheClipOffersIncrediblesThreeWaysIn() {
    expectEq(IslandAttachItem.allCases, [.chooseFile, .captureText, .screenshot],
             "clip: elegir, capturar texto, captura, en el orden de Incredible")
}

func testTheRegionPickerIsTheSystemsOwnAndSilent() {
    expectEq(RegionCapture.executable, "/usr/sbin/screencapture", "captura: la herramienta del sistema")
    let args = RegionCapture.arguments(to: "/tmp/x.png")
    expect(args.contains("-i"), "captura: selección de región interactiva")
    expect(args.contains("-x"), "captura: sin sonido de obturador")
    expectEq(args.last, "/tmp/x.png", "captura: el archivo va al final")
    let name = RegionCapture.fileName(id: UUID(uuidString: "12345678-0000-0000-0000-000000000000")!)
    expect(name.hasSuffix(".png"), "captura: PNG, sin pérdida para el OCR")
    expect(!name.contains("/"), "captura: el nombre nunca es una ruta")
}

func testEscapeInThePickerIsACancelNotAFailure() {
    expectEq(RegionCapture.outcome(exitCode: 0, bytesWritten: 2048), .captured, "captura: archivo con bytes")
    expectEq(RegionCapture.outcome(exitCode: 0, bytesWritten: nil), .cancelled,
             "captura: Escape sale con 0 y sin archivo")
    expectEq(RegionCapture.outcome(exitCode: 0, bytesWritten: 0), .cancelled, "captura: archivo vacío = nada")
    expectEq(RegionCapture.outcome(exitCode: 1, bytesWritten: nil), .failed, "captura: otro código es un fallo")
    expectEq(RegionCapture.outcome(exitCode: 1, bytesWritten: 99), .failed,
             "captura: un código de error no se toma aunque haya archivo")
}

func testRecognizedTextReadsTopToBottomLeftToRight() {
    // Vision's box origin is bottom-left: higher y is higher on the page.
    let lines = [
        RecognizedLine(text: "segunda", x: 0.1, y: 0.50),
        RecognizedLine(text: "derecha", x: 0.6, y: 0.805),
        RecognizedLine(text: "primera", x: 0.1, y: 0.80),
    ]
    expectEq(RecognizedText.join(lines), "primera derecha\nsegunda",
             "OCR: de arriba abajo; en la misma fila, de izquierda a derecha")
}

func testNoTextIsNothingToPaste() {
    expectEq(RecognizedText.join([]), nil, "OCR: sin líneas no hay texto")
    expectEq(RecognizedText.join([RecognizedLine(text: "  \n", x: 0, y: 0)]), nil,
             "OCR: solo espacios no es texto")
}

func testCapturedTextJoinsTheDraftWithoutGluingWords() {
    expectEq(IslandDraft.appending("hola", to: ""), "hola", "borrador vacío: el texto tal cual")
    expectEq(IslandDraft.appending("mundo", to: "hola"), "hola mundo", "se separa con un espacio")
    expectEq(IslandDraft.appending("mundo", to: "hola "), "hola mundo", "sin doble espacio")
    expectEq(IslandDraft.appending("  mundo \n", to: "hola"), "hola mundo", "el texto llega recortado")
    expectEq(IslandDraft.appending("   ", to: "hola"), "hola", "nada que añadir, nada cambia")
}

func testCapturedTextIsClippedLikeAnyInlineText() {
    let huge = String(repeating: "a", count: AttachmentPolicy.maxInlineChars + 500)
    let joined = IslandDraft.appending(huge, to: "")
    expect(joined.count <= AttachmentPolicy.maxInlineChars + 80,
           "OCR: un texto enorme se recorta con el mismo tope que un adjunto")
}

func testTheDropZonesSplitTheOpenCard() {
    let card = CGRect(x: 100, y: 0, width: 400, height: 200)
    expectEq(IslandDropZone.at(CGPoint(x: 150, y: 100), in: card), .ask, "izquierda: pregúntale")
    expectEq(IslandDropZone.at(CGPoint(x: 450, y: 100), in: card), .airDrop, "derecha: AirDrop")
    expectEq(IslandDropZone.at(CGPoint(x: 50, y: 100), in: card), nil, "fuera de la tarjeta: ninguna")
    expectEq(IslandDropZone.fallback, .ask, "soltar sobre la muesca sin zona: pregúntale")
}

func testADragOverTheNotchOpensTheDropCard() {
    let idle = SessionProjection()
    let dropping = IslandState.from(idle, pebbleHidden: false, dropping: true)
    expectEq(dropping.size, .card, "arrastre: la muesca se abre en tarjeta")
    expectEq(dropping.line, .dropZones, "arrastre: con sus zonas")
    let hidden = IslandState.from(idle, pebbleHidden: true, dropping: true)
    expectEq(hidden.line, .dropZones, "arrastre: también con la píldora oculta")
    let resting = IslandState.from(idle, pebbleHidden: false)
    expect(resting.line != .dropZones, "sin arrastre: nada cambia")
}

func testADragNeverCoversAQuestionOrWork() {
    var busy = SessionProjection()
    busy.kind = .processing(.thinking)
    let thinking = IslandState.from(busy, pebbleHidden: false, dropping: true)
    expectEq(thinking.line, .thinking, "arrastre: no tapa lo que está pensando")
    var asking = SessionProjection()
    asking.approvalQueue = [ApprovalRequest(requestId: "r1", toolName: "write_file", summary: "x", inputJSON: "{}")]
    let sheet = IslandState.from(asking, pebbleHidden: false, dropping: true)
    expect(sheet.approval != nil, "arrastre: la hoja sigue ahí")
    expect(sheet.line != .dropZones, "arrastre: nunca tapa una hoja")
    var noticed = SessionProjection()
    noticed.notice = .couldntHear
    let notice = IslandState.from(noticed, pebbleHidden: false, dropping: true)
    expectEq(notice.line, .couldntHear, "arrastre: no tapa un aviso con salida, como «Cancelado» y la tarea")
}

func testAStagedAttachmentKeepsTheFieldOpen() {
    expect(IslandComposing.active(focused: false, draft: "", confirmingClear: false,
                                  staged: 1, mainInFront: false),
           "un adjunto esperando mantiene el campo abierto")
    expect(!IslandComposing.active(focused: false, draft: "", confirmingClear: false,
                                   staged: 1, mainInFront: true),
           "con la ventana delante, el adjunto vive en la ventana")
    expect(IslandComposing.active(focused: false, draft: "  ", confirmingClear: false,
                                  staged: 0, mainInFront: false),
           "un borrador, aunque sean espacios, sigue siendo escribir")
    expect(!IslandComposing.active(focused: false, draft: "", confirmingClear: false,
                                   staged: 0, mainInFront: false),
           "nada que escribir: el campo se cierra")
}

/// Security review 16i-2 (MEDIUM): a folder's own size is its inode, so it
/// passed the 20 MB ceiling and was copied whole; a symlink pointed outside.
func testOnlyRegularFilesAreDropped() {
    expect(IslandDropFilter.keeps(isRegularFile: true, isSymbolicLink: false), "soltar: un archivo entra")
    expect(!IslandDropFilter.keeps(isRegularFile: false, isSymbolicLink: false), "soltar: una carpeta no")
    expect(!IslandDropFilter.keeps(isRegularFile: true, isSymbolicLink: true), "soltar: un enlace no")
    expect(!IslandDropFilter.keeps(isRegularFile: false, isSymbolicLink: true), "soltar: un enlace a carpeta no")
}

/// Security review 16i-2 (MEDIUM): the drag catcher takes plain clicks too.
/// It covers only dead space (the hardware notch at rest) unless a drag is on.
func testTheCatcherOnlyCoversTheHardwareNotchOrADrag() {
    let shape = CGRect(x: 600, y: 944, width: 200, height: 38)
    expectEq(IslandDropCatch.rect(shape: shape, hardwareNotch: true, resting: true, dropping: false), shape,
             "receptor: en reposo cubre la muesca física, donde nada se clica")
    expectEq(IslandDropCatch.rect(shape: shape, hardwareNotch: false, resting: true, dropping: false), .zero,
             "receptor: sin muesca física la píldora está sobre la barra de menús: nada")
    expectEq(IslandDropCatch.rect(shape: shape, hardwareNotch: true, resting: false, dropping: false), .zero,
             "receptor: abierta, la isla recibe el arrastre ella misma")
    expectEq(IslandDropCatch.rect(shape: shape, hardwareNotch: false, resting: false, dropping: true), shape,
             "receptor: durante un arrastre sigue la tarjeta")
}
