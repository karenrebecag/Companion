import CompanionCore
@testable import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Dictado y habla se guardan aparte del idioma de la interfaz, y el oído y
// las bocas leen esa elección al abrir la sesión (local reference;
// Incredible language pickers).

private let speechURL = "https://api.openai.com/v1/audio/speech"
private let elevenVoice = "brian"
private let elevenURL =
    "https://api.elevenlabs.io/v1/text-to-speech/\(elevenVoice)/stream?output_format=pcm_24000"

private func jsonObject(_ raw: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
}

private func bodyObject(_ request: URLRequest?) -> [String: Any] {
    guard let data = request?.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}

private func transcription(in json: [String: Any]) -> [String: Any] {
    let session = json["session"] as? [String: Any] ?? [:]
    let audio = session["audio"] as? [String: Any] ?? [:]
    let input = audio["input"] as? [String: Any] ?? [:]
    return input["transcription"] as? [String: Any] ?? [:]
}

@Test func spokenLanguagePersistsTheChoice() {
    withSpokenSuite { suite in
        expectEq(SpokenLanguagePreference.dictationCodes(in: suite), [],
                 "dictado: sin clave no hay idiomas elegidos")
        expectEq(SpokenLanguagePreference.speechCode(in: suite),
                 SpokenLanguagePreference.automatic,
                 "habla: sin clave es automático")
        expect(suite.object(forKey: SpokenLanguagePreference.dictationKey) == nil,
               "dictado: leer no escribe la clave")
        expect(suite.object(forKey: SpokenLanguagePreference.speechKey) == nil,
               "habla: leer no escribe la clave")

        SpokenLanguagePreference.setDictation(
            ["es", "fr", "es", "xx", "de", "it", "pt", "nl"], in: suite)
        expectEq(
            SpokenLanguagePreference.dictationCodes(in: suite),
            ["es", "fr", "de", "it", "pt"],
            "dictado: orden, sin duplicar, sin códigos ajenos, tope 5")
        expectEq(
            SpokenLanguagePreference.dictationCodes(in: suite),
            ["es", "fr", "de", "it", "pt"],
            "dictado: la misma suite vuelve a leer lo guardado")

        SpokenLanguagePreference.setSpeech("fr", in: suite)
        expectEq(SpokenLanguagePreference.speechCode(in: suite), "fr",
                 "habla: el código elegido queda guardado")
        expectEq(SpokenLanguagePreference.resolvedSpeechCode(in: suite, interface: .en), "fr",
                 "habla: un código del catálogo gana al dictado")
    }
}

@Test func spokenLanguageSttConfigReceivesTheLocale() {
    withSpokenSuite { suite in
        SpokenLanguagePreference.setDictation(["es", "fr"], in: suite)
        let chosen = jsonObject(OpenAITranscriber.sessionUpdateJSON(
            languages: SpokenLanguagePreference.transcriptionLanguages(in: suite),
            turnDetection: .serverVAD(silenceMs: 700)))
        let tx = transcription(in: chosen)
        expectEq(tx["model"] as? String, "gpt-transcribe",
                 "oído: sigue el modelo que acepta el VAD")
        expectEq(tx["languages"] as? [String], ["es", "fr"],
                 "oído: la lista elegida viaja en transcription.languages")

        SpokenLanguagePreference.setDictation([], in: suite)
        let automatic = jsonObject(OpenAITranscriber.sessionUpdateJSON(
            languages: SpokenLanguagePreference.transcriptionLanguages(in: suite),
            turnDetection: nil))
        let open = transcription(in: automatic)
        expect(open["languages"] == nil,
               "oído: sin elección no hay pista, escucha cualquiera")
        expectEq(open["model"] as? String, "gpt-transcribe",
                 "oído: automático no apaga el modelo")
    }
}

@Test @MainActor func spokenLanguageTtsReceivesTheLanguage() async {
    await withSpokenSuiteAsync { suite in
        SpokenLanguagePreference.setDictation(["fr"], in: suite)
        SpokenLanguagePreference.setSpeech(SpokenLanguagePreference.automatic, in: suite)
        let resolved = SpokenLanguagePreference.resolvedSpeechCode(in: suite, interface: .es)
        expectEq(resolved, "fr",
                 "habla: automático usa el primer idioma del dictado")

        let pick = SpeechPick("en")
        let secrets = ScriptedSecrets([
            .openAI: "sk-test", .elevenLabs: "sk_eleven_test",
        ])
        let openAI = ScriptedTransport()
        openAI.stub(url: speechURL, ScriptedReply(status: 200, body: Data([1])))
        let elevenTransport = ScriptedTransport()
        elevenTransport.stub(url: elevenURL, ScriptedReply(status: 200, body: Data([1])))

        let mouth = OpenAITTSClient(
            secrets: secrets, transport: openAI, language: .es,
            speechCode: { pick.code })
        let eleven = ElevenLabsTTSClient(
            secrets: secrets, transport: elevenTransport, language: .es,
            speechCode: { pick.code }, voiceID: { elevenVoice })
        let offline = AVSpeechFallback(language: .es, speechCode: { pick.code })
        pick.code = resolved

        do {
            _ = try await mouth.fetch("Bonjour.", voice: .marin)
        } catch {
            expect(false, "habla: OpenAI no debía tirar \(error)")
        }
        expectEq(bodyObject(openAI.requests.last)["instructions"] as? String,
                 SpokenLanguagePreference.instructions(for: "fr"),
                 "habla: OpenAI usa la instrucción del idioma resuelto, no la capturada al construir")

        do {
            _ = try await eleven.fetch("Bonjour.", voice: .marin)
        } catch {
            expect(false, "habla: ElevenLabs no debía tirar \(error)")
        }
        expectEq(
            bodyObject(elevenTransport.requests.last)["language_code"] as? String,
            "fr", "habla: ElevenLabs manda el código resuelto")
        expectEq(offline.voiceLocaleIdentifier, "fr-FR",
                 "habla: la voz del sistema usa la región de ese código")
    }
}

@Test @MainActor func spokenLanguageAutomaticFollowsTheInterfaceWhenDictationIsEmpty() async {
    await withSpokenSuiteAsync { suite in
        expectEq(SpokenLanguagePreference.resolvedSpeechCode(in: suite, interface: .es), "es",
                 "interfaz: sin dictado, automático es el idioma de la interfaz (es)")
        expectEq(SpokenLanguagePreference.resolvedSpeechCode(in: suite, interface: .en), "en",
                 "interfaz: sin dictado, automático es el idioma de la interfaz (en)")
        expectEq(SpokenLanguagePreference.resolvedSpeechCode(
            dictation: ["fr"], speech: SpokenLanguagePreference.automatic, interface: .es),
                 "fr", "interfaz: el dictado gana a la interfaz")
        expectEq(SpokenLanguagePreference.resolvedSpeechCode(
            dictation: ["fr"], speech: "de", interface: .es),
                 "de", "interfaz: lo elegido gana a todo")

        let secrets = ScriptedSecrets([
            .openAI: "sk-test", .elevenLabs: "sk_eleven_test",
        ])
        let openAI = ScriptedTransport()
        openAI.stub(url: speechURL, ScriptedReply(status: 200, body: Data([1])))
        let elevenTransport = ScriptedTransport()
        elevenTransport.stub(url: elevenURL, ScriptedReply(status: 200, body: Data([1])))
        let mouth = OpenAITTSClient(
            secrets: secrets, transport: openAI, language: .es, defaults: suite)
        let eleven = ElevenLabsTTSClient(
            secrets: secrets, transport: elevenTransport, language: .es,
            defaults: suite, voiceID: { elevenVoice })
        do {
            _ = try await mouth.fetch("Hola.", voice: .marin)
            _ = try await eleven.fetch("Hola.", voice: .marin)
        } catch {
            expect(false, "interfaz: las bocas no debían tirar \(error)")
        }
        expectEq(
            bodyObject(openAI.requests.last)["instructions"] as? String,
            SpokenLanguagePreference.instructions(for: "es"),
            "interfaz: OpenAI habla español con la suite intacta, como antes de la elección")
        expectEq(
            bodyObject(elevenTransport.requests.last)["language_code"] as? String,
            "es", "interfaz: ElevenLabs manda es con la suite intacta")
        expectEq(
            AVSpeechFallback(language: .es, defaults: suite).voiceLocaleIdentifier,
            "es-MX", "interfaz: la voz del sistema conserva es-MX con la suite intacta")
    }
}

@Test @MainActor func spokenLanguageCacheVariantChangesWithTheCode() {
    let pick = SpeechPick("es")
    let secrets = ScriptedSecrets([.openAI: "sk-test", .elevenLabs: "sk_eleven_test"])
    let eleven = ElevenLabsTTSClient(
        secrets: secrets, transport: ScriptedTransport(), language: .es,
        speechCode: { pick.code }, voiceID: { elevenVoice })
    let openAI = OpenAITTSClient(
        secrets: secrets, transport: ScriptedTransport(), language: .es,
        speechCode: { pick.code })

    let elevenSpanish = eleven.cacheVariant(voice: .marin)
    let openAISpanish = openAI.cacheVariant(voice: .marin)
    pick.code = "fr"
    expect(eleven.cacheVariant(voice: .marin) != elevenSpanish,
           "caché: ElevenLabs no repite audio de otro idioma con la misma frase")
    expect(openAI.cacheVariant(voice: .marin) != openAISpanish,
           "caché: OpenAI no repite audio de otro idioma con la misma frase")
    pick.code = "es"
    expectEq(eleven.cacheVariant(voice: .marin), elevenSpanish,
             "caché: volver al mismo idioma vuelve a la misma clave (ElevenLabs)")
    expectEq(openAI.cacheVariant(voice: .marin), openAISpanish,
             "caché: volver al mismo idioma vuelve a la misma clave (OpenAI)")
}

@Test func spokenLanguageNormalizesAndIgnoresMalformedStorage() {
    withSpokenSuite { suite in
        suite.set("es", forKey: SpokenLanguagePreference.dictationKey)
        expectEq(SpokenLanguagePreference.dictationCodes(in: suite), [],
                 "almacén: un String suelto no es una lista de idiomas")
        suite.set([1, 2], forKey: SpokenLanguagePreference.dictationKey)
        expectEq(SpokenLanguagePreference.dictationCodes(in: suite), [],
                 "almacén: una lista de números no es una lista de idiomas")
        suite.set(7, forKey: SpokenLanguagePreference.speechKey)
        expectEq(SpokenLanguagePreference.speechCode(in: suite),
                 SpokenLanguagePreference.automatic,
                 "almacén: un habla que no es String se lee como automático")

        suite.set([" ES ", "Fr\n"], forKey: SpokenLanguagePreference.dictationKey)
        expectEq(SpokenLanguagePreference.dictationCodes(in: suite), ["es", "fr"],
                 "almacén: blancos y mayúsculas se normalizan al leer")
        SpokenLanguagePreference.setDictation([" ES "], in: suite)
        expectEq(suite.array(forKey: SpokenLanguagePreference.dictationKey) as? [String],
                 ["es"], "almacén: se guarda normalizado")
    }
}

@Test func spokenLanguageSkipsUnknownDictationCodesWhenResolving() {
    expectEq(SpokenLanguagePreference.resolvedSpeechCode(
        dictation: ["xx", "de"], speech: SpokenLanguagePreference.automatic, interface: .en),
             "de", "habla: automático salta el código ajeno y toma el primero válido")
}

@Test @MainActor func spokenLanguageUnsupportedLocaleFallsBack() async {
    await withSpokenSuiteAsync { suite in
        suite.set(["xx", "es-MX"], forKey: SpokenLanguagePreference.dictationKey)
        suite.set("zz", forKey: SpokenLanguagePreference.speechKey)
        expectEq(SpokenLanguagePreference.transcriptionLanguages(in: suite), [],
                 "caída: un código ajeno no entra a la lista del oído")
        let json = jsonObject(OpenAITranscriber.sessionUpdateJSON(
            languages: SpokenLanguagePreference.transcriptionLanguages(in: suite),
            turnDetection: nil))
        expect(transcription(in: json)["languages"] == nil,
               "caída: el oído no manda el código ajeno ni una lista vacía")

        expectEq(SpokenLanguagePreference.speechCode(in: suite),
                 SpokenLanguagePreference.automatic,
                 "caída: un código de habla ajeno se lee como automático")
        expectEq(SpokenLanguagePreference.resolvedSpeechCode(in: suite, interface: .en), "en",
                 "caída: sin dictado válido, automático es el idioma de la interfaz")
        expectEq(SpokenLanguagePreference.resolvedSpeechCode(
            dictation: [], speech: "", interface: .es), "es",
                 "caída: un código de habla vacío es automático, nunca vacío")
        expectEq(SpokenLanguagePreference.wireLanguageCode("zz"), "en",
                 "caída: ElevenLabs recibe un código del catálogo")
        expectEq(SpokenLanguagePreference.regionalIdentifier(for: "zz"), "en-US",
                 "caída: la voz del sistema cae a en-US")
        expectEq(SpokenLanguagePreference.regionalIdentifier(for: "es"), "es-MX",
                 "caída: el español conserva la región del modelo en el dispositivo")
        expectEq(SpokenLanguagePreference.regionalIdentifier(for: "no"), "nb-NO",
                 "caída: el noruego del catálogo tiene región")

        SpokenLanguagePreference.setSpeech("not-a-language", in: suite)
        expectEq(SpokenLanguagePreference.speechCode(in: suite),
                 SpokenLanguagePreference.automatic,
                 "caída: guardar un código ajeno deja automático")

        let pick = SpeechPick("zz")
        let secrets = ScriptedSecrets([
            .openAI: "sk-test", .elevenLabs: "sk_eleven_test",
        ])
        let openAI = ScriptedTransport()
        openAI.stub(url: speechURL, ScriptedReply(status: 200, body: Data([1])))
        let elevenTransport = ScriptedTransport()
        elevenTransport.stub(url: elevenURL, ScriptedReply(status: 200, body: Data([1])))
        let mouth = OpenAITTSClient(
            secrets: secrets, transport: openAI, language: .en,
            speechCode: { pick.code })
        let eleven = ElevenLabsTTSClient(
            secrets: secrets, transport: elevenTransport, language: .en,
            speechCode: { pick.code }, voiceID: { elevenVoice })
        do {
            _ = try await mouth.fetch("Hi.", voice: .marin)
            _ = try await eleven.fetch("Hi.", voice: .marin)
        } catch {
            expect(false, "caída: las bocas no debían tirar \(error)")
        }
        expectEq(bodyObject(openAI.requests.last)["instructions"] as? String,
                 SpokenLanguagePreference.instructions(for: "en"),
                 "caída: OpenAI habla inglés, no una instrucción vacía")
        expectEq(
            bodyObject(elevenTransport.requests.last)["language_code"] as? String,
            "en", "caída: ElevenLabs no manda el código ajeno ni cadena vacía")
        expectEq(
            AVSpeechFallback(language: .en, speechCode: { pick.code }).voiceLocaleIdentifier,
            "en-US", "caída: la voz del sistema no usa el código ajeno")
    }
}

private final class SpeechPick: @unchecked Sendable {
    var code: String
    init(_ code: String) { self.code = code }
}
