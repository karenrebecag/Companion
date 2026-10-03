import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// The -1743 follow-up: a closed-set action Finder refused because Companion
// lacks Automation is spoken as where to turn it on, in the user's language,
// naming the app's switch under Companion (macOS lists it there).

@Test func aRefusedAutomationIsSpokenAsWhereToTurnItOn() {
    let refused = ParentToolOutcome(
        ok: false, output: BridgeCode.permissionRequired + ": " + BridgeMessages.automationRequired, target: "Finder")
    for language in AppLanguage.allCases {
        let line = DecisionCopy.acted(refused, tool: "system", language)
        expectEq(line, DecisionCopy.automationRequired(app: "Finder", language), "\(language): la frase del permiso")
        expect(line.contains("Finder") && line.contains("Companion"), "\(language): nombra la app y la fila: \(line)")
    }
    expect(DecisionCopy.automationRequired(app: "Finder", .es).contains("Automatización"), "es: el panel")
    expect(DecisionCopy.automationRequired(app: "Finder", .en).contains("Automation"), "en: el panel")
}

@Test func aRefusalWithoutAnAppNameStillReadsAsASentence() {
    expect(DecisionCopy.automationRequired(app: "", .es).contains("esa app"), "es: sin nombre")
    expect(DecisionCopy.automationRequired(app: "", .en).contains("that app"), "en: sin nombre")
}

/// The browser's permission_required means another permission and has its own copy.
@Test func aBrowserPermissionRefusalKeepsTheBrowsersCopy() {
    let browser = ParentToolOutcome(ok: false, output: BridgeCode.permissionRequired + ": x", target: "")
    expectEq(DecisionCopy.acted(browser, tool: "browser_click", .es),
             ParentToolCopy.status("browser_click", browser, .es), "la copia del navegador")
}

@Test func anyOtherActedOutcomeKeepsItsStatus() {
    let done = ParentToolOutcome(ok: true, output: "done", target: "")
    expectEq(DecisionCopy.acted(done, tool: "system", .es), "Hecho: system.", "un exito no cambia")
}
