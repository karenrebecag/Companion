import CompanionCore
import CompanionTestKit
import Testing

// Wave 16a-4 (spec §5 fila 8). Sin herramienta de click el cerebro delegaba
// "acepta el permiso" a Claude Code, que pedía permiso para un osascript.
// Con look/click declarados, el prompt los nombra y prohíbe delegar la UI.

@Test @MainActor func promptSightTests() {
    for language in [AppLanguage.es, .en] {
        let with = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true, parentToolsEnabled: true,
            handsEnabled: true, sightEnabled: true, language: language)
        for tool in ["look", "click", "scroll", "menu"] {
            expect(with.contains(tool), "16a-4 \(language): nombra \(tool)")
        }
        let without = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true, parentToolsEnabled: true,
            handsEnabled: true, language: language)
        expect(!without.contains("(click)"), "16a-4 \(language): sin vista declarada no promete click")
        expect(!without.contains("(look)"), "16a-4 \(language): ni look")
    }
    let es = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: true, parentToolsEnabled: true,
        handsEnabled: true, sightEnabled: true, language: .es)
    expect(es.contains("Pulsar botones o menús no se delega"), "16a-4 es: pulsar no se delega")
    expect(es.contains("primero look"), "16a-4 es: mirar antes de pulsar")
    let en = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: true, parentToolsEnabled: true,
        handsEnabled: true, sightEnabled: true, language: .en)
    expect(en.contains("Pressing buttons or menus is never delegated"), "16a-4 en: never delegated")
    expect(en.contains("look first"), "16a-4 en: look before click")
    // Brief manos-escribir-en-notas, D1: with no field to type into, the model
    // retried type_text three times and never tried menu (log 2026-10-02).
    expect(es.contains("Archivo > Nueva nota"), "D1 es: sin campo, crear el documento con menu")
    expect(en.contains("File > New Note"), "D1 en: no field, create the document with menu")
}
