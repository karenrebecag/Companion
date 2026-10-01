import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// El idioma no es barniz de UI: los prompts deciden en qué habla el modelo.
// Hasta la Wave 9 estaban fijos en español, así que un usuario en inglés
// recibía un asistente contestándole en otro idioma y hablándole de
// "encargos". El inglés es la fuente; el español, la traducción.

@Test @MainActor func appLanguageTests() {
    testResolutionFollowsTheSystem()
    testPreferenceBeatsTheSystem()
    testChatPromptSpeaksTheLanguage()
    testEscalationSpeaksTheLanguage()
    testToolDescriptionsTravelInTheLanguage()
    testConfigCarriesTheLanguage()
    testThePreferenceIsActuallyWired()
    testTheSpeechLocaleFollowsTheLanguage()
}

/// El patrón de bug de este repo: la decisión existe, nadie la invoca. Sin
/// esto, `Config.language` sería siempre .en y todo lo demás, código muerto.
@MainActor func testThePreferenceIsActuallyWired() {
    let saved = LanguagePreference.stored
    defer { LanguagePreference.stored = saved }

    LanguagePreference.stored = .es
    expectEq(LanguagePreference.current, .es,
             "preferencia: elegir español manda sobre el sistema")
    LanguagePreference.stored = nil
    expectEq(LanguagePreference.current,
             AppLanguage.resolved(system: Locale.preferredLanguages),
             "preferencia: sin elección, la app sigue al sistema")
}

@MainActor func testResolutionFollowsTheSystem() {
    expectEq(AppLanguage.resolved(system: ["es-MX", "en-US"]), .es,
             "idioma: un español regional es español")
    expectEq(AppLanguage.resolved(system: ["en-GB"]), .en,
             "idioma: un inglés regional es inglés")
    expectEq(AppLanguage.resolved(system: ["fr-FR", "de-DE"]), .en,
             "idioma: lo que la app no habla cae al inglés, que es la fuente")
    expectEq(AppLanguage.resolved(system: []), .en,
             "idioma: sin sistema que consultar, la fuente")
    expectEq(AppLanguage.resolved(system: ["de-DE", "es-ES"]), .es,
             "idioma: se respeta el orden de preferencia del sistema")
}

@MainActor func testPreferenceBeatsTheSystem() {
    expectEq(AppLanguage.resolved(preferred: .en, system: ["es-MX"]), .en,
             "idioma: elegirlo en Ajustes gana sobre el sistema")
    expectEq(AppLanguage.resolved(preferred: nil, system: ["es-MX"]), .es,
             "idioma: sin elección explícita manda el sistema")
}

/// Un prompt en inglés que se cuela en español es el bug entero: el modelo
/// obedece al prompt, no a la UI.
@MainActor func testChatPromptSpeaksTheLanguage() {
    let english = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: true, language: .en)
    expect(!hasSpanish(english),
           "prompt: en inglés no queda una sola palabra española")
    expect(english.contains("Karen"), "prompt: el nombre sobrevive")
    expect(english.lowercased().contains("english"),
           "prompt: se le pide contestar en inglés")

    let spanish = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: true, language: .es)
    expect(spanish.contains("Español"),
           "prompt: el español sigue siendo el de siempre")
    expect(spanish.contains("delegate"),
           "prompt: el nombre de la tool no se traduce")
}

@MainActor func testEscalationSpeaksTheLanguage() {
    expect(!hasSpanish(Escalation.executorRole(.en)),
           "rol: el especialista recibe su contrato en inglés")
    expect(!hasSpanish(ContextBlock.replyHint(.voice, language: .en) ?? ""),
           "pista: la voz pide brevedad en inglés (Wave 10a: vive en ContextBlock)")
    expect(!hasSpanish(Escalation.jobDoneAnnouncement("clean the desk", .en)),
           "aviso: el cierre del encargo se narra en inglés")
    // Y el español llega en español, no regenerado en inglés.
    expect(Escalation.jobDoneAnnouncement("limpiar", .es)
        .contains("en pantalla"),
           "español: el acuse viaja en el idioma de la sesión")
}

/// El schema viaja al servidor: cambiar el idioma no puede romper el JSON
/// ni renombrar la tool.
@MainActor func testToolDescriptionsTravelInTheLanguage() {
    let english = ToolSpec.delegate(.en)
    expect(!hasSpanish(english.description),
           "tool: la descripción viaja en inglés")
    expectEq(english.name, "delegate", "tool: el nombre nunca se traduce")
    let json = english.encodeRealtime()
    expect(json.contains("\"delegate\"") && json.contains("\"parameters\""),
           "tool: sigue siendo el JSON plano que espera Realtime")
    expectEq(ToolSpec.resolveApproval(.en).name, "resolve_approval",
             "tool: resolve_approval tampoco cambia de nombre")
}

/// El reconocedor no escucha "un idioma", escucha un locale. Sin región,
/// SFSpeechRecognizer se queda sin el modelo on-device que sí tiene para la
/// variante regional.
@MainActor func testTheSpeechLocaleFollowsTheLanguage() {
    expectEq(AppLanguage.en.speechLocaleIdentifier, "en-US",
             "locale: al inglés se le escucha en inglés")
    expectEq(AppLanguage.es.speechLocaleIdentifier, "es-MX",
             "locale: el español conserva el regional que ya funcionaba")
}

@MainActor func testConfigCarriesTheLanguage() {
    expectEq(Config.default.language, .en,
             "config: sin nada configurado, la fuente")
    var config = Config()
    config.language = .es
    expectEq(config.language, .es, "config: el idioma viaja con lo demás")
}

/// Heurística deliberada: tildes y signos de apertura. No detecta todo el
/// español, pero sí lo que se cuela al portar un prompt a medias.
private func hasSpanish(_ text: String) -> Bool {
    text.contains { "áéíóúñ¿¡Á É Í Ó Ú Ñ".contains($0) && $0 != " " }
}
