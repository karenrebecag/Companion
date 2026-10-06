import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// El oído del hold es el del dispositivo y escucha un idioma a la vez: el
// primero que se eligió en Dictado, o el de la interfaz si no hay ninguno.

@Test func onDeviceLocaleFollowsDictationElseTheInterface() {
    withSpokenSuite { suite in
        expectEq(SpokenLanguagePreference.onDeviceLocale(interface: .es, defaults: suite),
                 "es-MX", "oído: sin dictado, el idioma de la interfaz (es)")
        expectEq(SpokenLanguagePreference.onDeviceLocale(interface: .en, defaults: suite),
                 "en-US", "oído: sin dictado, el idioma de la interfaz (en)")

        SpokenLanguagePreference.setDictation(["fr", "de"], in: suite)
        expectEq(SpokenLanguagePreference.onDeviceLocale(interface: .es, defaults: suite),
                 "fr-FR", "oído: con dictado, el primero con su región")

        SpokenLanguagePreference.setDictation(["it"], in: suite)
        expectEq(SpokenLanguagePreference.onDeviceLocale(interface: .es, defaults: suite),
                 "it-IT", "oído: un cambio llega en la siguiente lectura")

        suite.set(["xx", "  "], forKey: SpokenLanguagePreference.dictationKey)
        expectEq(SpokenLanguagePreference.onDeviceLocale(interface: .en, defaults: suite),
                 "en-US", "oído: un dictado sin códigos válidos es automático")
    }
}

@Test @MainActor func analyzerEarFallsBackWhenTheEngineLacksTheDictationLocale() async {
    let engine = FakeTranscriberEngine()
    engine.unsupportedLocales = ["tlh-US"]
    engine.finalOnFinish = ["hola"]
    let ear = AnalyzerTranscriber(
        engine: engine, vocabulary: { [] }, fallbackLocale: { "es-MX" })
    do {
        try await ear.start(localeIdentifier: "tlh-US")
    } catch {
        expect(false, "oído: el hold no debía fallar por un idioma sin modelo: \(error)")
    }
    expectEq(engine.locales, ["es-MX"],
             "oído: sin modelo para el dictado, escucha en el idioma de la interfaz")
    await ear.append(frame(0x01))
    expectEq(await ear.stop(), "hola", "oído: el hold sí oye")

    let supported = FakeTranscriberEngine()
    let direct = AnalyzerTranscriber(
        engine: supported, vocabulary: { [] }, fallbackLocale: { "es-MX" })
    try? await direct.start(localeIdentifier: "fr-FR")
    expectEq(supported.locales, ["fr-FR"], "oído: con modelo, escucha el idioma de dictado")
}

@Test @MainActor func analyzerEarPreparesTheFallbackNotTheMissingLocale() async {
    let engine = FakeTranscriberEngine()
    engine.installed = false
    engine.unsupportedLocales = ["tlh-US"]
    let ear = AnalyzerTranscriber(
        engine: engine, vocabulary: { [] }, fallbackLocale: { "es-MX" })
    await ear.prepare(localeIdentifier: "tlh-US")
    expectEq(engine.installLocales, ["es-MX"],
             "oído: la descarga es la del idioma que sí se puede oír")
}

@Test @MainActor func analyzerEarWithNothingHearableDoesNotLoopOrThrow() async {
    let engine = FakeTranscriberEngine()
    engine.unsupportedLocales = ["tlh-US", "es-MX"]
    let ear = AnalyzerTranscriber(
        engine: engine, vocabulary: { [] }, fallbackLocale: { "es-MX" })
    do {
        try await ear.start(localeIdentifier: "tlh-US")
    } catch {
        expect(false, "oído: sin nada que oír no tira, termina como un hold sin modelo: \(error)")
    }
    await ear.prepare(localeIdentifier: "tlh-US")
    expectEq(engine.locales, [], "oído: no abre ninguna corrida")
    expectEq(engine.installLocales, [], "oído: no descarga lo que no existe")
}

@MainActor private func earRuntime() -> (ClassicRuntime, FakeTranscriber) {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = ""
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: ScriptedSynth(), chat: ScriptedChat(),
        thread: ScriptedThread())
    return (runtime, transcriber)
}

@Test @MainActor func classicRestartAfterAnEmptyHoldReadsTheLocalePerStart() async {
    let (runtime, transcriber) = earRuntime()
    runtime.earLocale = { _ in "fr-FR" }
    await runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(transcriber.locale, "fr-FR",
             "oído: tras un hold vacío, el reinicio escucha el idioma de dictado")

    runtime.earLocale = { $0.speechLocaleIdentifier }
    await runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(transcriber.locale, "es-MX",
             "oído: sin dictado vuelve al idioma de la interfaz, leído en cada arranque")
}

@Test @MainActor func classicListenAndRealtimeOpenUseTheDictationLocale() async {
    let classic = makeVoiceHarness(key: nil, autoEvents: [], language: .es)
    let classicRuntime = await classic.session.classic
    classicRuntime.earLocale = { _ in "fr-FR" }
    await classic.session.start()
    await pumpUntil("oído: clásico armado") {
        classic.watch.latest.state == .listening && classic.watch.latest.pipeline == .classic
    }
    expectEq(classic.transcriber.locale, "fr-FR",
             "oído: el hold clásico escucha el primer idioma de dictado")

    let ear = ScriptedTranscriber()
    let realtime = makeVoiceHarness(language: .es, realtimeEar: ear)
    let realtimeRuntime = await realtime.session.classic
    realtimeRuntime.earLocale = { _ in "de-DE" }
    await realtime.session.start()
    await pumpUntil("oído: realtime armado") {
        realtime.watch.latest.state == .listening && realtime.watch.latest.pipeline == .realtime
    }
    expectEq(ear.locale, "de-DE", "oído: la apertura realtime usa la misma regla")
}

@Test @MainActor func analyzerEarUsesTheFallbackWhileAPickedLocaleDownloads() async {
    let engine = FakeTranscriberEngine()
    engine.notInstalledLocales = ["fr-FR"]
    let ear = AnalyzerTranscriber(
        engine: engine, vocabulary: { [] }, fallbackLocale: { "es-MX" })
    try? await ear.start(localeIdentifier: "fr-FR")
    expectEq(engine.locales, ["es-MX"],
             "oído: con el idioma nuevo aún sin modelo, este hold escucha en el de la interfaz")
    await pumpUntil("oído: la descarga del idioma elegido arranca") {
        engine.installLocales == ["fr-FR"]
    }
    expectEq(engine.installLocales, ["fr-FR"],
             "oído: se descarga el idioma elegido, no el de respaldo")
    _ = await ear.stop()
    try? await ear.start(localeIdentifier: "fr-FR")
    expectEq(engine.locales, ["es-MX", "fr-FR"],
             "oído: el siguiente hold ya usa el idioma elegido")
}

@Test @MainActor func analyzerEarKeepsMissingAssetsWhenTheFallbackIsNotReadyEither() async {
    let engine = FakeTranscriberEngine()
    engine.notInstalledLocales = ["fr-FR", "es-MX"]
    let ear = AnalyzerTranscriber(
        engine: engine, vocabulary: { [] }, fallbackLocale: { "es-MX" })
    try? await ear.start(localeIdentifier: "fr-FR")
    expectEq(engine.locales, [], "oído: sin ningún modelo listo no se abre corrida")
}
