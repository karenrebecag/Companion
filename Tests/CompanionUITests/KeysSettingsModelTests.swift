import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing

/// Wave 15c-6: Ajustes → Claves. §8 requires the Keychain to be read only
/// when the pane is shown, never at app boot — `refresh()` is the seam that
/// draws that line, so it gets its own test apart from save/delete.
@Test @MainActor func keysSettingsModelTests() async {
    await pinLanguage {
        testRefreshOnlyOnDemandNeverAtInit()
        testSaveTrimsWritesAndClearsTheField()
        testSaveRejectsEmptyOrWhitespaceOnly()
        testDeleteClearsTheSavedState()
        testProvidersAreIndependent()
        testWithoutASecretStoreNothingCrashes()
        testMaskShowsOnlyTheEnds()
        testSaveExposesOnlyTheMask()
        testRefreshMasksTheStoredKey()
        testCerebrasRowSavesItsOwnKey()
        testThereIsNoGroqRowAndAStoredGroqKeyStaysHidden()
        await testAFailedDeleteSaysSoAndKeepsTheRow()
        testElevenLabsRowSavesItsOwnKey()
        await testElevenLabsRowCopy()
    }
}

/// 15f-7a: ElevenLabs gets the same row as Cerebras — its own key, masked.
@MainActor func testElevenLabsRowSavesItsOwnKey() {
    let store = TestSecretStore()
    let model = KeysSettingsModel(secrets: store)
    model.elevenLabsField = "  sk_0123456789abcdefQWER  "
    model.save(.elevenLabs)
    expectEq(try? store.read(.elevenLabs), "sk_0123456789abcdefQWER", "elevenlabs: se guarda recortada")
    expectEq(model.elevenLabsField, "", "elevenlabs: el campo no conserva la clave")
    expect(model.elevenLabsSaved, "elevenlabs: marcada como guardada")
    expectEq(model.masked[.elevenLabs], "sk_0••••QWER", "elevenlabs: solo la máscara")
    expect(!model.openAISaved && !model.cerebrasSaved, "elevenlabs: no toca las otras")
    model.delete(.elevenLabs)
    expectEq(try? store.read(.elevenLabs), nil, "elevenlabs: borrar la quita")
    expect(!model.elevenLabsSaved, "elevenlabs: deja de estar guardada")
}

@MainActor func testElevenLabsRowCopy() async {
    for (language, privacy) in [
        (AppLanguage.en, "With ElevenLabs, the text of each reply is sent to ElevenLabs to be voiced."),
        (.es, "Con ElevenLabs, el texto de cada respuesta se envía a ElevenLabs para darle voz."),
    ] {
        await Localized.scoped(to: language) {
            expectEq(Localized.string("settings.keys.elevenlabs"), "ElevenLabs", "elevenlabs: título (\(language))")
            expectEq(Localized.string("settings.keys.elevenlabs.placeholder"), "sk_…",
                     "elevenlabs: placeholder (\(language))")
            expectEq(Localized.string("settings.keys.elevenlabs.privacy"), privacy,
                     "elevenlabs: privacidad (\(language))")
        }
    }
}

/// L2 (security review 2026-09-24): a Keychain that refuses the delete
/// used to be swallowed, and the row cleared as if the key were gone.
@MainActor func testAFailedDeleteSaysSoAndKeepsTheRow() async {
    for (language, wording) in [(AppLanguage.en, "Could not delete the key."),
                                (.es, "No se pudo borrar la clave.")] {
        await Localized.scoped(to: language) {
            let store = RefusingDeleteStore([.openAI: "sk-proj-0123456789abcdWXYZ"])
            let model = KeysSettingsModel(secrets: store)
            model.refresh()
            model.delete(.openAI)
            expectEq(model.errorText, wording, "L2: el error se dice (\(language))")
            expectEq(model.masked[.openAI], "sk-p••••WXYZ", "L2: la fila sigue (\(language))")
        }
    }
}

private final class RefusingDeleteStore: SecretStore, @unchecked Sendable {
    private let values: [SecretKey: String]
    init(_ values: [SecretKey: String]) { self.values = values }
    func read(_ key: SecretKey) throws -> String? { values[key] }
    func write(_ key: SecretKey, value: String) throws {}
    func delete(_ key: SecretKey) throws { throw SecretStoreError.denied }
}

/// 15e-2 (spec §4 row 7): Groq is gone from Ajustes. Only OpenAI, Cerebras
/// and (15f-7a) ElevenLabs have a row, and a Groq key left in the Keychain
/// from before 15e never surfaces as a saved row.
@MainActor func testThereIsNoGroqRowAndAStoredGroqKeyStaysHidden() {
    expectEq(KeysSettingsModel.Provider.allCases.map(\.secretKey),
             [.openAI, .cerebras, .elevenLabs], "ajustes: OpenAI, Cerebras y ElevenLabs")
    let store = TestSecretStore([.groq: "gsk_leftover0000000000"])
    let model = KeysSettingsModel(secrets: store)
    model.refresh()
    expect(model.masked.isEmpty, "ajustes: la clave vieja de Groq no aparece")
}

/// 15c-7, Karen: "no se le entiende nada a tu interfaz" — after saving, the
/// field went blank and nothing said which key was in. The row now shows a
/// mask; never more than the first and last four characters.
@MainActor func testMaskShowsOnlyTheEnds() {
    expectEq(KeysSettingsModel.mask("gsk_abcdefghijklmnopfACP"), "gsk_••••fACP",
             "máscara: 4 + •••• + 4")
    expectEq(KeysSettingsModel.mask("short"), "••••", "máscara: una clave corta no se revela")
    expectEq(KeysSettingsModel.mask("   "), "••••", "máscara: vacía no se revela")
}

@MainActor func testSaveExposesOnlyTheMask() {
    let store = TestSecretStore()
    let model = KeysSettingsModel(secrets: store)
    model.cerebrasField = "csk_abcdefghijklmnopfACP"
    model.save(.cerebras)
    expectEq(model.masked[.cerebras], "csk_••••fACP", "guardar: queda la máscara")
    expectEq(model.cerebrasField, "", "guardar: el campo no conserva la clave")
    expect(!String(describing: model.masked).contains("abcdefghijklmnop"),
           "guardar: el estado nunca contiene la clave completa")
}

@MainActor func testRefreshMasksTheStoredKey() {
    let store = TestSecretStore([.openAI: "sk-proj-0123456789abcdWXYZ"])
    let model = KeysSettingsModel(secrets: store)
    expect(model.masked[.openAI] == nil, "refresh: nada antes de aparecer")
    model.refresh()
    expectEq(model.masked[.openAI], "sk-p••••WXYZ", "refresh: máscara de la guardada")
    model.delete(.openAI)
    expect(model.masked[.openAI] == nil, "borrar: la máscara se va")
}

@MainActor func testCerebrasRowSavesItsOwnKey() {
    let store = TestSecretStore()
    let model = KeysSettingsModel(secrets: store)
    model.cerebrasField = "csk-0123456789abcdefwrjz"
    model.save(.cerebras)
    expectEq(try? store.read(.cerebras), "csk-0123456789abcdefwrjz", "cerebras: se guarda")
    expect(model.cerebrasSaved, "cerebras: marcada como guardada")
    expect(!model.openAISaved, "cerebras: no toca OpenAI")
}

@MainActor func testRefreshOnlyOnDemandNeverAtInit() {
    let store = TestSecretStore([.openAI: "sk-existing-key-000000"])
    let model = KeysSettingsModel(secrets: store)
    expect(!model.openAISaved, "claves: no lee el Keychain al construirse")
    model.refresh()
    expect(model.openAISaved, "claves: refresh sí lee la presencia")
}

@MainActor func testSaveTrimsWritesAndClearsTheField() {
    let store = TestSecretStore()
    let model = KeysSettingsModel(secrets: store)
    model.openAIField = "  sk-abcdefghijklmnopqrst  "
    model.save(.openAI)
    expectEq(try? store.read(.openAI), "sk-abcdefghijklmnopqrst", "claves: guarda recortada")
    expectEq(model.openAIField, "", "claves: el campo se limpia — nunca guarda el valor")
    expect(model.openAISaved, "claves: queda marcada como guardada")
    expect(model.errorText == nil, "claves: sin error")
}

@MainActor func testSaveRejectsEmptyOrWhitespaceOnly() {
    let store = TestSecretStore()
    let model = KeysSettingsModel(secrets: store)
    model.cerebrasField = "   "
    model.save(.cerebras)
    expectEq(try? store.read(.cerebras), nil, "claves: vacío no escribe")
    expect(!model.cerebrasSaved, "claves: vacío no queda guardado")
    expect(model.errorText != nil, "claves: vacío marca error")
}

@MainActor func testDeleteClearsTheSavedState() {
    let store = TestSecretStore([.cerebras: "csk_existing00000000"])
    let model = KeysSettingsModel(secrets: store)
    model.refresh()
    expect(model.cerebrasSaved, "claves: arranca guardada")
    model.delete(.cerebras)
    expectEq(try? store.read(.cerebras), nil, "claves: borra del secret store")
    expect(!model.cerebrasSaved, "claves: deja de estar guardada")
}

@MainActor func testProvidersAreIndependent() {
    let store = TestSecretStore()
    let model = KeysSettingsModel(secrets: store)
    model.openAIField = "sk-onlyopenaikeyvalue"
    model.save(.openAI)
    expect(model.openAISaved && !model.cerebrasSaved, "claves: guardar una no toca la otra")
}

/// Settings can render before a `ChatViewModel` exists (`chat` is
/// optional); the model must degrade quietly instead of crashing.
@MainActor func testWithoutASecretStoreNothingCrashes() {
    let model = KeysSettingsModel()
    model.refresh()
    expect(!model.openAISaved && !model.cerebrasSaved, "claves: sin secretStore, nada guardado")
    model.openAIField = "sk-anything-at-all-0000"
    model.save(.openAI)
    expect(!model.openAISaved, "claves: sin secretStore, save no truena y no guarda")
}
