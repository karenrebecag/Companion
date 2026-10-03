import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Security review 2026-09-25 (LOW-3). The router read the Keychain on every
// `cacheVariant` access — cache lookup, stream and cache store each asked
// again — so one sentence cost several reads, and a key saved or deleted
// mid-sentence stored ElevenLabs audio under the OpenAI variant. The mouth
// is now decided once per sentence and that decision keys its cache.

private let voice = "Gubgw9l4dtIoQA9YZHgx"

@Test @MainActor func testTheRouterReadsTheKeychainOncePerSentence() async {
    let dir = makeTTSTempDir("router-once")
    defer { removeDir(dir) }
    let secrets = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
    let router = MouthRouter(
        elevenLabs: ScriptedMouth("eleven"), openAI: ScriptedMouth("openai"),
        secrets: secrets, voiceID: { voice })
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: router, playback: FakePlay(),
        fallback: FakeFallback(), voice: .marin)
    _ = await speak(synth, "Hola.")
    expectEq(secrets.reads, 1, "L3: una frase, una lectura del llavero")

    let two = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
    let router2 = MouthRouter(
        elevenLabs: ScriptedMouth("eleven"), openAI: ScriptedMouth("openai"),
        secrets: two, voiceID: { voice })
    let synth2 = SpeechSynthesis(
        cache: PhraseCache(directory: makeTTSTempDir("router-twice")), fetcher: router2,
        playback: FakePlay(), fallback: FakeFallback(), voice: .marin)
    _ = await speak(synth2, "Uno.", "Dos.")
    expectEq(two.reads, 2, "L3: dos frases, dos lecturas (con o sin prefetch)")
}

/// A mouth that deletes the ElevenLabs key while it is voicing — Settings
/// changed mid-sentence.
private final class KeyDroppingMouth: TTSFetching, @unchecked Sendable {
    let secrets: ScriptedSecrets
    init(secrets: ScriptedSecrets) { self.secrets = secrets }
    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        // One locked call, not a read-then-write through `values`.
        try secrets.delete(.elevenLabs)
        return Data("eleven:\(text)".utf8)
    }
    func cacheVariant(voice: VoiceID) -> String { "eleven" }
}

@Test @MainActor func testTheCachedVariantIsTheMouthThatProducedTheAudio() async {
    let dir = makeTTSTempDir("router-variant")
    defer { removeDir(dir) }
    let secrets = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
    let router = MouthRouter(
        elevenLabs: KeyDroppingMouth(secrets: secrets), openAI: ScriptedMouth("openai"),
        secrets: secrets, voiceID: { voice })
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: router, playback: FakePlay(),
        fallback: FakeFallback(), voice: .marin)
    _ = await speak(synth, "Hola.")
    let base = PhraseCache(directory: dir)
    expect(stored(base.scoped("eleven"), "Hola."),
           "L3: el audio de ElevenLabs se guarda bajo ElevenLabs")
    expect(!stored(base.scoped("openai"), "Hola."),
           "L3: nunca bajo la variante de OpenAI aunque la clave cambie a mitad")
}

@Test @MainActor func testTheRoutersResolvedMouthIsFixedForTheSentence() {
    let secrets = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
    let router = MouthRouter(
        elevenLabs: ScriptedMouth("eleven"), openAI: ScriptedMouth("openai"),
        secrets: secrets, voiceID: { voice })
    let mouth = router.resolved()
    expectEq(secrets.reads, 1, "L3: decidir es una lectura")
    secrets.values.removeValue(forKey: .elevenLabs)
    expectEq(mouth.cacheVariant(voice: .marin), "eleven",
             "L3: la decisión no cambia con el llavero")
    expectEq(secrets.reads, 1, "L3: y la variante no vuelve a leerlo")
    expectEq(router.resolved().cacheVariant(voice: .marin), "openai",
             "L3: la frase siguiente sí ve el cambio")
}

private func stored(_ cache: PhraseCache, _ phrase: String) -> Bool {
    do { return try cache.data(for: phrase) != nil } catch { return false }
}

private func removeDir(_ url: URL) {
    do { try FileManager.default.removeItem(at: url) } catch {
        // Temp dir cleanup; a leftover never changes an assertion.
    }
}
