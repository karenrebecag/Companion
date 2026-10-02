import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Brief manos-escribir-en-notas, D2: in Notes with ~88 notes, `look` spent its
// 600 ms on the note list and never reached the toolbar, so "Nueva nota" had
// no id (9 of 9 looks: elements=0). A window's toolbar is walked first.

@Test func windowChildrenWalkTheToolbarFirst() {
    let window = "AXWindow"
    expectEq(ScreenRoles.childOrder(parentRole: window, childRoles: ["AXSplitGroup", "AXToolbar", "AXButton"]),
             [1, 0, 2], "la barra de herramientas antes que la lista")
    expectEq(ScreenRoles.childOrder(parentRole: window, childRoles: ["AXGroup", "AXToolbar", "AXScrollArea", "AXToolbar"]),
             [1, 3, 0, 2], "dos barras: las dos primero, en su orden")
    expectEq(ScreenRoles.childOrder(parentRole: window, childRoles: ["AXToolbar", "AXGroup"]), [0, 1],
             "la barra ya va primero")
    expectEq(ScreenRoles.childOrder(parentRole: window, childRoles: ["AXToolbar", "AXToolbar"]), [0, 1],
             "solo barras")
    expectEq(ScreenRoles.childOrder(parentRole: window, childRoles: ["AXGroup", "AXScrollArea"]), [0, 1],
             "sin barra: el orden de AX")
    // A role the walk had no time to read comes back empty: not a toolbar.
    expectEq(ScreenRoles.childOrder(parentRole: window, childRoles: ["", "AXToolbar", ""]), [1, 0, 2],
             "rol sin leer: no es barra")
    expectEq(ScreenRoles.childOrder(parentRole: window, childRoles: []), [], "sin hijos")
}

// Only a window is reordered: one extra role read per child, once per walk.
@Test func onlyAWindowsChildrenAreReordered() {
    for parent in ["AXSplitGroup", "AXGroup", "AXSheet", "AXScrollArea", ""] {
        expectEq(ScreenRoles.childOrder(parentRole: parent, childRoles: ["AXGroup", "AXToolbar"]), [0, 1],
                 "\(parent): el orden de AX")
    }
    expect(!ScreenRoles.readsChildRoles(of: "AXGroup"), "fuera de una ventana no se leen roles de más")
    expect(ScreenRoles.readsChildRoles(of: "AXWindow"), "en la ventana sí")
}

@Test func theOrderIsAlwaysAPermutation() {
    let roles = ["AXToolbar", "AXGroup", "", "AXToolbar", "AXSplitGroup", "AXButton"]
    for parent in ["AXWindow", "AXGroup"] {
        let order = ScreenRoles.childOrder(parentRole: parent, childRoles: roles)
        expectEq(order.sorted(), Array(roles.indices), "\(parent): todos los hijos, una vez")
    }
}

// AXScreen is not testable without Accessibility, so its source is checked:
// the walk asks Core both whether to read the roles and in which order.
@Test func theWalkUsesTheCoreOrder() throws {
    let root = try #require(Conformance.repoRoot())
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/CompanionServices/Accessibility/AXScreen.swift"),
        encoding: .utf8)
    expect(source.contains("ScreenRoles.readsChildRoles(of: role)"), "AXScreen pregunta si leer los roles")
    expect(source.contains("ScreenRoles.childOrder(parentRole: role"), "AXScreen ordena con Core")
}
