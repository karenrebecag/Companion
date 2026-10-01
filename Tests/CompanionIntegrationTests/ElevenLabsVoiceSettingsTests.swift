import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15f-6 (spec §4 fila 9): Ajustes › Voz elige la voz de ElevenLabs y la
// muestra suena por la MISMA boca que el hold (`MouthRouter`), no por un
// cliente aparte.

private let anaMaria = "m7yTemJqdIqrcNleANfX"
private let regina = "9Godp7dNohUvXk6qp0gS"

private func elevenURL(_ voice: String) -> String {
    "https://api.elevenlabs.io/v1/text-to-speech/\(voice)/stream?output_format=pcm_24000"
}

/// Every test writes into its own suite, never the user's defaults.
@MainActor private func isolatedPreference(_ name: String) -> () -> Void {
    let suite = "companion.tests.eleven.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    ElevenLabsVoicePreference.store = defaults
    return { ElevenLabsVoicePreference.store = .standard }
}

@Test @MainActor func elevenLabsVoiceSettingsTests() async {
    testThePresetsAreTheBenchShortlist()
    testPickingAPresetWritesTheConfigVoice()
    await testAnInvalidCustomIDIsRefusedAndNotPersisted()
    testAValidCustomIDIsTrimmedAndPersisted()
    testTheElevenLabsSectionNeedsTheKey()
    await testTheElevenLabsSectionCopy()
    await testTheSampleGoesThroughTheRouterWithTheChosenVoice()
    await testWithoutAKeyTheSampleGoesThroughOpenAI()
}

/// §8.3: the five candidates plus the old default, Karen's pick first.
@MainActor func testThePresetsAreTheBenchShortlist() {
    let presets = ElevenLabsMouth.presets
    expectEq(presets.map(\.name),
             ["Ana María", "Regina", "Jorge", "Antonio", "Cristina Campos", "Brian"],
             "presets: la lista corta del banco, Ana María primero")
    expectEq(presets.map(\.id),
             [anaMaria, regina, "Rt1JHkPO27QCUX6Nd5bV", "htFfPSZGJwjBv1CL0aMD",
              "CaJslL1xziwefCeTNzHv", "Gubgw9l4dtIoQA9YZHgx"],
             "presets: ids de la clave del banco")
    expectEq(presets.first?.id, Config.defaultElevenLabsVoiceID,
             "presets: el primero es el default")
    expect(presets.allSatisfy { ElevenLabsTTSClient.isValidVoiceID($0.id) },
           "presets: todos pasan la validación del cliente")
}

@MainActor func testPickingAPresetWritesTheConfigVoice() {
    let restore = isolatedPreference("preset")
    defer { restore() }
    expectEq(ElevenLabsVoicePreference.voiceID, Config.defaultElevenLabsVoiceID,
             "preferencia: sin valor guardado vale el default")

    let model = ElevenLabsVoiceModel()
    expectEq(model.selectedPreset?.name, "Ana María", "picker: arranca en Ana María")
    let pick = ElevenLabsMouth.presets[1]
    model.select(pick)
    expectEq(ElevenLabsVoicePreference.voiceID, regina, "picker: la preferencia cambia a Regina")
    expectEq(model.voiceID, regina, "picker: el modelo refleja la voz")
    expectEq(model.selectedPreset, pick, "picker: Regina seleccionada")
    expectEq(Config(elevenLabsVoiceID: ElevenLabsVoicePreference.voiceID).elevenLabsVoiceID,
             regina, "picker: Config.elevenLabsVoiceID sale de la preferencia")
    expectEq(ElevenLabsVoiceModel().voiceID, regina, "picker: sobrevive a otro modelo (relanzar)")
}

@MainActor func testAnInvalidCustomIDIsRefusedAndNotPersisted() async {
    let restore = isolatedPreference("invalid")
    defer { restore() }
    await Localized.scoped(to: .es) {
        let model = ElevenLabsVoiceModel()
        for bad in ["abc%2Fdef", "../v1/user", "vozñandú", "", "   ",
                    String(repeating: "a", count: 65), "a b", "id'; DROP", "🎙️"] {
            model.customField = bad
            model.applyCustom()
            expectEq(model.errorText, Localized.string("settings.voice.eleven.invalid"),
                     "custom: '\(bad)' se rechaza con texto de error")
            expectEq(ElevenLabsVoicePreference.voiceID, Config.defaultElevenLabsVoiceID,
                     "custom: '\(bad)' no se guarda")
            expectEq(model.voiceID, Config.defaultElevenLabsVoiceID,
                     "custom: '\(bad)' no cambia la voz en pantalla")
        }
        expect(!Localized.string("settings.voice.eleven.invalid").hasPrefix("settings."),
               "custom: el error está en el catálogo")
    }
}

@MainActor func testAValidCustomIDIsTrimmedAndPersisted() {
    let restore = isolatedPreference("valid")
    defer { restore() }
    let model = ElevenLabsVoiceModel()
    model.customField = "abc%"
    model.applyCustom()
    expect(model.errorText != nil, "custom: primero un error")
    model.customField = "  XyZ0123456789  \n"
    model.applyCustom()
    expect(model.errorText == nil, "custom: un id válido limpia el error")
    expectEq(ElevenLabsVoicePreference.voiceID, "XyZ0123456789", "custom: se guarda recortado")
    expect(model.selectedPreset == nil, "custom: un id fuera de la lista no es un preset")
}

@MainActor func testTheElevenLabsSectionNeedsTheKey() {
    let restore = isolatedPreference("key")
    defer { restore() }
    let secrets = ScriptedSecrets([.openAI: "sk-test"])
    let model = ElevenLabsVoiceModel()
    model.secrets = secrets
    model.refresh()
    expect(!model.hasKey, "sección: sin clave de ElevenLabs no hay selector")
    secrets.values[.elevenLabs] = "   "
    model.refresh()
    expect(!model.hasKey, "sección: una clave en blanco no cuenta")
    secrets.values[.elevenLabs] = "sk_eleven_test_0000"
    model.refresh()
    expect(model.hasKey, "sección: con clave aparece el selector")
    secrets.values.removeValue(forKey: .elevenLabs)
    model.refresh()
    expect(!model.hasKey, "sección: borrar la clave la esconde de nuevo")
}

@MainActor func testTheElevenLabsSectionCopy() async {
    for (language, noKey) in [
        (AppLanguage.es, "Sin clave de ElevenLabs se usa la voz de OpenAI de arriba."),
        (.en, "Without an ElevenLabs key, the OpenAI voice above is used."),
    ] {
        await Localized.scoped(to: language) {
            expectEq(Localized.string("settings.voice.eleven.nokey"), noKey,
                     "copy: sin clave (\(language))")
            for key in ["settings.voice.eleven.header", "settings.voice.eleven.blurb",
                        "settings.voice.eleven.custom", "settings.voice.eleven.custom.placeholder",
                        "settings.voice.eleven.custom.apply", "settings.voice.eleven.custom.label",
                        "settings.voice.eleven.invalid"] {
                expect(Localized.string(key) != key, "copy: \(key) existe (\(language))")
            }
        }
    }
}

/// The preview is the real mouth: the router reads the key, the ElevenLabs
/// client reads the voice the picker just wrote.
@MainActor func testTheSampleGoesThroughTheRouterWithTheChosenVoice() async {
    let restore = isolatedPreference("sample")
    defer { restore() }
    let transport = ScriptedTransport()
    transport.stub(url: elevenURL(regina), ScriptedReply(status: 200, body: Data([1, 2])))
    let secrets = ScriptedSecrets([.openAI: "sk-test", .elevenLabs: "sk_eleven_test_0000"])
    let openAI = ScriptedMouth("openai")
    let router = MouthRouter(
        elevenLabs: ElevenLabsTTSClient(
            secrets: secrets, transport: transport, language: .es,
            voiceID: { ElevenLabsVoicePreference.voiceID }),
        openAI: openAI, secrets: secrets,
        voiceID: { ElevenLabsVoicePreference.voiceID })
    let preview = VoicePreview(
        sampler: TTSVoiceSampler(fetcher: openAI, playback: FakePlay()),
        mouth: TTSVoiceSampler(fetcher: router, playback: FakePlay()))

    let model = ElevenLabsVoiceModel()
    model.select(ElevenLabsMouth.presets[1])
    preview.playMouth(.marin)
    expect(preview.playingMouth, "muestra: marca que está sonando")
    await pumpUntil("muestra: termina") { !preview.playingMouth }

    expect(preview.errorText == nil, "muestra: sin error")
    let request = transport.requests.last
    expectEq(request?.url?.absoluteString, elevenURL(regina),
             "muestra: ElevenLabs con la voz elegida (Regina)")
    let body = request?.httpBody.flatMap {
        try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
    }
    expectEq(body?["text"] as? String, VoicePreview.sampleText, "muestra: la frase fija")
    expectEq(openAI.calls, [], "muestra: OpenAI no se usa con clave y voz")
}

@MainActor func testWithoutAKeyTheSampleGoesThroughOpenAI() async {
    let restore = isolatedPreference("nokey")
    defer { restore() }
    let transport = ScriptedTransport()
    let secrets = ScriptedSecrets([.openAI: "sk-test"])
    let openAI = ScriptedMouth("openai")
    let router = MouthRouter(
        elevenLabs: ElevenLabsTTSClient(
            secrets: secrets, transport: transport, language: .es,
            voiceID: { ElevenLabsVoicePreference.voiceID }),
        openAI: openAI, secrets: secrets,
        voiceID: { ElevenLabsVoicePreference.voiceID })
    let preview = VoicePreview(
        sampler: TTSVoiceSampler(fetcher: openAI, playback: FakePlay()),
        mouth: TTSVoiceSampler(fetcher: router, playback: FakePlay()))
    preview.playMouth(.cedar)
    await pumpUntil("muestra sin clave: termina") { !preview.playingMouth }
    expectEq(openAI.calls, [VoicePreview.sampleText], "muestra sin clave: suena por OpenAI")
    expect(transport.requests.isEmpty, "muestra sin clave: ninguna petición a ElevenLabs")
    expect(preview.errorText == nil, "muestra sin clave: sin error")
}
