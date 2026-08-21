import CompanionUI
import Foundation
import Testing

@Test @MainActor func menuPlanTests() {
    testEditCommandsStayFixedWhenShortcutsRebind()
    testAttachKeyEquivalentFollowsShortcutSet()
    testMissingShortcutKeepsItemWithoutKey()
    testInvalidKeyCodeLeavesEmptyEquivalent()
    testDefaultPlanHasFourSectionsAndVoiceItems()
    testSystemEditKeys()
}

@MainActor func testEditCommandsStayFixedWhenShortcutsRebind() {
    // Rebinding C to attach must not steal Copiar from the Edit menu.
    let hijack = ShortcutSet(shortcuts: [
        Shortcut(action: .attach, keyCode: 8, modifiers: KeyModifiers(command: true)),
    ])
    let plan = MenuPlan.build(shortcuts: hijack)
    let copy = item(plan, .copy)
    expectEq(copy?.keyEquivalent, "c", "menu: copiar sigue en c")
    expect(copy?.modifiers.command == true, "menu: copiar sigue en Cmd")
    expect(copy?.modifiers.shift == false, "menu: copiar sin shift")
    expectEq(item(plan, .cut)?.keyEquivalent, "x", "menu: cortar fijo en x")
    expectEq(item(plan, .paste)?.keyEquivalent, "v", "menu: pegar fijo en v")
    expectEq(item(plan, .selectAll)?.keyEquivalent, "a", "menu: seleccionar fijo en a")
}

@MainActor func testAttachKeyEquivalentFollowsShortcutSet() {
    let first = ShortcutSet(shortcuts: [
        Shortcut(action: .attach, keyCode: 32, modifiers: KeyModifiers(command: true)),
    ])
    expectEq(item(MenuPlan.build(shortcuts: first), .attach)?.keyEquivalent, "u",
             "menu: adjuntar refleja Cmd+U")

    let rebound = ShortcutSet(shortcuts: [
        Shortcut(
            action: .attach, keyCode: 0,
            modifiers: KeyModifiers(command: true, shift: true)),
    ])
    let attach = item(MenuPlan.build(shortcuts: rebound), .attach)
    expectEq(attach?.keyEquivalent, "a", "menu: adjuntar refleja el atajo nuevo")
    expect(attach?.modifiers.shift == true, "menu: el shift viaja con el atajo")
}

@MainActor func testMissingShortcutKeepsItemWithoutKey() {
    let plan = MenuPlan.build(shortcuts: ShortcutSet(shortcuts: []))
    let attach = item(plan, .attach)
    expect(attach != nil, "menu: adjuntar sigue en el menu sin atajo")
    expectEq(attach?.keyEquivalent, "", "menu: sin atajo no miente una tecla")
    expect(item(plan, .newConversation) != nil, "menu: nueva conversacion existe")
    expect(item(plan, .history) != nil, "menu: historial existe")
    expect(item(plan, .settings) != nil, "menu: ajustes existe")
}

@MainActor func testInvalidKeyCodeLeavesEmptyEquivalent() {
    let set = ShortcutSet(shortcuts: [
        Shortcut(action: .attach, keyCode: 999, modifiers: KeyModifiers(command: true)),
    ])
    expectEq(item(MenuPlan.build(shortcuts: set), .attach)?.keyEquivalent, "",
             "menu: tecla sin equivalente Cocoa se deja vacia")
}

@MainActor func testDefaultPlanHasFourSectionsAndVoiceItems() {
    let plan = MenuPlan.build(shortcuts: .defaults)
    expectEq(plan.map { $0.title }, ["Companion", "Edición", "Conversación", "Ventana"],
             "menu: las cuatro secciones de una app de Mac")
    expect(item(plan, .toggleVoice) != nil, "menu: turno de voz visible")
    expect(item(plan, .toggleMute) != nil, "menu: mute visible")
    expect(item(plan, .hangUp) != nil, "menu: colgar visible")
    expectEq(item(plan, .toggleVoice)?.keyEquivalent, " ",
             "menu: el default de voz es espacio")
}

@MainActor func testSystemEditKeys() {
    let plan = MenuPlan.build(shortcuts: .defaults)
    expectEq(item(plan, .undo)?.keyEquivalent, "z", "menu: deshacer z")
    expect(item(plan, .redo)?.modifiers.shift == true, "menu: rehacer con shift")
    expectEq(item(plan, .pastePlain)?.keyEquivalent, "v", "menu: pegar plano en v")
    expect(item(plan, .pastePlain)?.modifiers.option == true,
           "menu: pegar plano con option")
    expectEq(item(plan, .quit)?.keyEquivalent, "q", "menu: salir en q")
    expectEq(item(plan, .hide)?.keyEquivalent, "h", "menu: ocultar en h")
}

@MainActor
private func item(_ plan: [MenuSectionPlan], _ command: MenuCommand) -> MenuItemPlan? {
    for section in plan {
        for candidate in section.items where candidate.command == command {
            return candidate
        }
    }
    return nil
}
