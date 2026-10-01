import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 16a-1 (spec §5 filas 1). La vista del padre: el árbol de Accesibilidad
// de la ventana de delante, numerado para poder pulsarlo, recortado y sin el
// valor de un campo seguro. Como el `scan` de Incredible.

@Test @MainActor func screenScanTests() {
    testActionableElementsGetIdsAndTextDoesNot()
    testASecureFieldNeverShowsItsValue()
    testTheScanIsCappedAndSaysSo()
    testEmptyAndDuplicateTextIsDropped()
    testTheRenderNamesTheWindowAndApp()
    testALongFieldValueShowsItsEnd()
}

private func node(_ role: String, _ label: String, value: String? = nil, subrole: String = "",
                  secure: Bool = false) -> ScanNode {
    ScanNode(role: role, subrole: subrole, label: label, value: value, secure: secure)
}

private func walk(_ nodes: [ScanNode], partial: Bool = false) -> ScreenWalk {
    ScreenWalk(nodes: nodes, partial: partial, window: "Google - Safari", generation: 3)
}

@MainActor func testActionableElementsGetIdsAndTextDoesNot() {
    let scan = ScreenScan.build(walk([
        node("AXStaticText", "", value: "google.com quiere usar tu ubicación"),
        node("AXButton", "Permitir"),
        node("AXButton", "No permitir"),
        node("AXTextField", "Buscar", value: "restaurantes"),
        node("AXLink", "Imágenes"),
    ]), app: "Safari")
    expectEq(scan.elements.map(\.id), [1, 2, 3, 4], "ids: solo lo accionable, en orden")
    expectEq(scan.elements.map(\.node), [1, 2, 3, 4], "ids: apuntan al nodo del recorrido")
    expectEq(scan.elements.first?.label, "Permitir", "ids: la etiqueta")
    expectEq(scan.generation, 3, "ids: atados a su recorrido")
    let text = scan.render()
    expect(text.contains(#"[1] button "Permitir""#), "render: botón con id")
    expect(text.contains(#"[3] field "Buscar" = "restaurantes""#), "render: campo con valor")
    expect(text.contains(#"[4] link "Imágenes""#), "render: enlace")
    expect(text.contains("- google.com quiere usar tu ubicación"), "render: texto sin id")
    expectEq(scan.element(id: 2)?.label, "No permitir", "busca por id")
    expect(scan.element(id: 9) == nil, "id inexistente: nada")
}

@MainActor func testASecureFieldNeverShowsItsValue() {
    let scan = ScreenScan.build(walk([
        node("AXTextField", "Contraseña", value: "hunter2", subrole: "AXSecureTextField", secure: true),
    ]), app: "Safari")
    let text = scan.render()
    expect(!text.contains("hunter2"), "seguro: nunca el valor")
    expect(text.contains(#"[1] password field "Contraseña""#), "seguro: se sabe que existe")
}

@MainActor func testTheScanIsCappedAndSaysSo() {
    let many = (1...400).map { node("AXButton", "Botón \($0)") }
    let scan = ScreenScan.build(walk(many), app: "Mail")
    expectEq(scan.elements.count, ScreenScan.maxElements, "tope de elementos")
    expect(scan.partial, "truncado: parcial")
    expect(scan.render().count <= ScreenScan.maxChars + 200, "tope de caracteres")
    expect(scan.render().contains("partial"), "truncado: lo dice")
    let walkCut = ScreenScan.build(walk([node("AXButton", "OK")], partial: true), app: "Mail")
    expect(walkCut.render().contains("partial"), "recorrido cortado: también lo dice")
    let long = ScreenScan.build(walk([node("AXStaticText", "", value: String(repeating: "x", count: 900))]),
                                app: "Notes")
    expect(long.render().count < 400, "un texto largo se recorta")
}

@MainActor func testEmptyAndDuplicateTextIsDropped() {
    let scan = ScreenScan.build(walk([
        node("AXStaticText", "", value: "  "),
        node("AXStaticText", "", value: "Hola"),
        node("AXStaticText", "", value: "Hola"),
        node("AXGroup", "contenedor"),
        node("AXButton", ""),
    ]), app: "Notes")
    expectEq(scan.render().components(separatedBy: "- Hola").count - 1, 1, "texto repetido: una vez")
    expect(!scan.render().contains("contenedor"), "grupos: no se listan")
    expectEq(scan.elements.count, 1, "botón sin etiqueta: sigue siendo pulsable")
    expect(scan.render().contains(#"[1] button """#), "botón sin etiqueta: se ve vacío")
}

@MainActor func testTheRenderNamesTheWindowAndApp() {
    let text = ScreenScan.build(walk([node("AXButton", "OK")]), app: "Safari").render()
    expect(text.hasPrefix(#"window "Google - Safari" (Safari)"#), "cabecera: ventana y app")
}

/// Live 2026-09-25: a terminal's text area showed "Last login…" — the start
/// of the buffer. What matters is the end: the prompt and the latest output.
@MainActor func testALongFieldValueShowsItsEnd() {
    let buffer = "Last login: ayer" + String(repeating: " x", count: 300) + " karen$ ls -la"
    let text = ScreenScan.build(walk([node("AXTextArea", "shell", value: buffer)]), app: "Terminal")
        .render()
    expect(text.contains("karen$ ls -la"), "valor largo: el final")
    expect(!text.contains("Last login"), "valor largo: no el principio")
}

// Code review 16 (MEDIUM): a menu step picked the first label that merely
// contained the word — "Exportar" before "Exportar como PDF…" or the reverse.
@Test @MainActor func menuStepPrefersTheExactLabel() {
    expectEq(WindowTitles.bestMatch(["Exportar como PDF…", "Exportar"], for: "exportar"), 1,
             "menú: la etiqueta exacta gana a la que la contiene")
    expectEq(WindowTitles.bestMatch(["Guardar", "Guardar como…"], for: "guardar como"), 1,
             "menú: 'guardar como' no es 'Guardar'")
    expectEq(WindowTitles.bestMatch(["Archivo", "Edición"], for: "edicion"), 1,
             "menú: sin acentos ni mayúsculas")
    expectEq(WindowTitles.bestMatch(["Exportar como PDF…"], for: "exportar"), 0,
             "menú: sin exacta, la que la contiene")
    expect(WindowTitles.bestMatch(["Archivo"], for: "Ventana") == nil, "menú: nada")
}
