import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// The projection that leaves the device about a window. The rule it holds:
// controls and their labels only. Text rows, field and text-area content, and
// the window title never appear, and a diff carries flags, not values.

private func node(
    _ role: String, label: String = "", value: String? = nil, secure: Bool = false,
    enabled: Bool = true, focused: Bool = false
) -> ScanNode {
    ScanNode(role: role, subrole: secure ? "AXSecureTextField" : "", label: label, value: value,
             secure: secure, enabled: enabled, focused: focused)
}

private func snapshot(_ nodes: [ScanNode], window: String = "Notas privadas", partial: Bool = false)
    -> ScreenSnapshot
{
    ScreenSnapshot(walk: ScreenWalk(nodes: nodes, partial: partial, window: window, generation: 1))
}

@Test func theOutlineControlHasNoValueProperty() throws {
    let outline = ScreenOutline(snapshot: snapshot([node("AXTextField", label: "Título", value: "mi nota")]))
    let control = try #require(outline.controls.first)
    expect(!Mirror(reflecting: control).children.contains { $0.label == "value" },
           "el tipo que sale no tiene campo value")
    expect(control.hasValue, "el contenido se reporta solo como hasValue")
}

@Test func contentOfFieldsAndAreasNeverLeaves() {
    let outline = ScreenOutline(snapshot: snapshot([
        node("AXTextField", label: "Título", value: "contenido-campo"),
        node("AXTextArea", label: "Cuerpo", value: "contenido-area"),
        node("AXComboBox", label: "Idioma", value: "contenido-combo"),
        node("AXSearchField", label: "Buscar", value: "contenido-buscar"),
        node("AXSlider", label: "Volumen", value: "0.4"),
    ]))
    let text = String(describing: outline)
    for leaked in ["contenido-campo", "contenido-area", "contenido-combo", "contenido-buscar"] {
        expect(!text.contains(leaked), "sin contenido de \(leaked)")
    }
    expectEq(outline.controls.map(\.label), ["Título", "Cuerpo", "Idioma", "Buscar", "Volumen"],
             "las etiquetas de los controles sí salen")
}

@Test func textRowsAndHeadingsAreExcluded() {
    let outline = ScreenOutline(snapshot: snapshot([
        node("AXStaticText", value: "Fila de lista"),
        node("AXHeading", value: "Encabezado"),
        node("AXButton", label: "Guardar"),
    ]))
    expectEq(outline.controls.map(\.role), ["AXButton"], "solo el control")
    expect(!String(describing: outline).contains("Fila de lista"), "ni filas ni encabezados")
}

@Test func theWindowTitleNeverLeaves() {
    let outline = ScreenOutline(snapshot: snapshot([node("AXButton", label: "Guardar")], window: "Notas privadas"))
    expect(!String(describing: outline).contains("Notas privadas"), "el título de la ventana no sale")
}

@Test func aSecureFieldLeavesWithoutValueOrHasValue() {
    let outline = ScreenOutline(snapshot: snapshot([node("AXTextField", label: "Clave", value: "hunter2", secure: true)]))
    expectEq(outline.controls.map(\.label), ["Clave"], "el nombre del campo seguro")
    expect(outline.controls.first?.hasValue == false, "sin valor, ni siquiera como bandera")
    expect(!String(describing: outline).contains("hunter2"), "el secreto no sale")
}

@Test func aLabelIsClippedToEightyCharacters() throws {
    let long = String(repeating: "x", count: 200)
    let outline = ScreenOutline(snapshot: snapshot([node("AXButton", label: long)]))
    let label = try #require(outline.controls.first?.label)
    expect(label.count <= 81, "80 caracteres y la marca de corte")
}

@Test func theElementCapCutsAndSaysPartial() {
    let buttons = (0..<200).map { node("AXButton", label: "b\($0)") }
    let outline = ScreenOutline(snapshot: snapshot(buttons))
    expectEq(outline.controls.count, ScreenScan.maxElements, "tope de 150 controles")
    expect(outline.partial, "lo cortado se dice parcial")
}

@Test func aDiffCarriesFlagsNeverValues() throws {
    let before = snapshot([node("AXTextField", label: "Título", value: "valor-antes")])
    let after = snapshot([
        node("AXTextField", label: "Título", value: "valor-despues"),
        node("AXStaticText", value: "fila nueva"),
        node("AXButton", label: "Guardar", focused: true),
    ])
    let diff = ScreenOutlineDiff(diff: ScreenDiff(before: before, after: after))

    let text = String(describing: diff)
    expect(!text.contains("valor-antes") && !text.contains("valor-despues"), "ni antes ni después")
    expect(!text.contains("fila nueva"), "una fila nueva no sale")
    expectEq(diff.appeared.map(\.label), ["Guardar"], "aparece el control")
    let change = try #require(diff.changed.first)
    expect(change.label == "Título" && change.valueChanged && !change.enabledChanged && !change.focusedChanged,
           "solo la bandera de valor cambió")
}
