import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 14a. El hold elige roles de producto; el desplegable de chat no entra.

@Test @MainActor func voiceStackTests() async {
    testOpenAIFillsEveryRole()
    testOllamaIsTheBrainWhenNothingElseIsPresent()
    testNothingYieldsEmptyRoles()
    testTheChatPickerIsNotAnInput()
    await testAHoldStackIgnoresTheChatPicker()
    testAStoredGroqKeyNeverReachesTheHold()
    await testAPressWithAStoredGroqKeyStillPicksOpenAIMini()
    testElevenLabsIsTheMouthOnlyWithKeyAndVoice()
    await testAPressWithAnElevenLabsKeyNamesItsMouth()
    testKarensVoiceIsTheDefaultAndStaysOverridable()
}

/// 15f-7a: the mouth is ElevenLabs only with its key AND a chosen voice;
/// the log names the model, never the voice id.
@MainActor func testElevenLabsIsTheMouthOnlyWithKeyAndVoice() {
    let both = VoiceStackResolver.resolve(
        secrets: [.openAI: true, .elevenLabs: true],
        appleSpeech: true, localModel: nil, elevenLabsVoiceID: "Gubgw9l4dtIoQA9YZHgx")
    expectEq(both.mouth, VoiceRole(id: "elevenlabs/eleven_flash_v2_5", provider: "elevenlabs"),
             "elevenlabs: clave + voz = boca ElevenLabs")
    expect(both.logLine.contains("mouth=elevenlabs/eleven_flash_v2_5"),
           "elevenlabs: el log nombra el modelo (\(both.logLine))")
    expect(!both.logLine.contains("Gubgw9l4dtIoQA9YZHgx"), "elevenlabs: el log no lleva la voz")
    expectEq(both.sight, VoiceRole(id: "gpt-4o-mini", provider: "openai"),
             "elevenlabs: la vista sigue en OpenAI")

    let alone = VoiceStackResolver.resolve(
        secrets: [.elevenLabs: true], appleSpeech: true, localModel: nil,
        elevenLabsVoiceID: "Gubgw9l4dtIoQA9YZHgx")
    expectEq(alone.mouth?.provider, "elevenlabs", "elevenlabs: no necesita la clave de OpenAI")

    let noVoice = VoiceStackResolver.resolve(
        secrets: [.openAI: true, .elevenLabs: true],
        appleSpeech: true, localModel: nil, elevenLabsVoiceID: "  ")
    expectEq(noVoice.mouth, VoiceRole(id: "gpt-4o-mini-tts", provider: "openai"),
             "elevenlabs: sin voz elegida sigue OpenAI")

    let noKey = VoiceStackResolver.resolve(
        secrets: [.openAI: true], appleSpeech: true, localModel: nil,
        elevenLabsVoiceID: "Gubgw9l4dtIoQA9YZHgx")
    expectEq(noKey.mouth, VoiceRole(id: "gpt-4o-mini-tts", provider: "openai"),
             "elevenlabs: sin clave sigue OpenAI")
}

/// 15f-7a: the press reads the ElevenLabs key and the configured voice.
@MainActor func testAPressWithAnElevenLabsKeyNamesItsMouth() async {
    let h = makeVoiceHarness(key: "sk-test")
    h.secrets.values[.elevenLabs] = "sk_eleven_test_0000"
    await h.session.hold()
    let stack = await h.session.lastStack
    expectEq(stack?.mouth?.id, "elevenlabs/eleven_flash_v2_5",
             "press: con clave de ElevenLabs y la voz por defecto, la boca es ElevenLabs")
}

/// Karen's blind pick on 2026-09-25 (15f-6): "Ana María", es-MX, shared
/// library. A saved key is all it takes.
@MainActor func testKarensVoiceIsTheDefaultAndStaysOverridable() {
    expectEq(Config().elevenLabsVoiceID, "m7yTemJqdIqrcNleANfX", "config: Ana María por defecto")
    expectEq(Config(elevenLabsVoiceID: "otra").elevenLabsVoiceID, "otra", "config: se puede cambiar")
}

/// 15e-2 (spec §4 row 8): Groq is gone from the app. A key Karen pasted
/// before 15e may still sit in the Keychain; it must not pick any role —
/// with OpenAI the brain is gpt-4o-mini, alone it yields no brain at all.
@MainActor func testAStoredGroqKeyNeverReachesTheHold() {
    let both = VoiceStackResolver.resolve(
        secrets: [.openAI: true, .groq: true],
        appleSpeech: true,
        localModel: nil)
    expectEq(both.brain, VoiceRole(id: "gpt-4o-mini", provider: "openai"),
             "groq+openai: el cerebro es gpt-4o-mini, nunca Groq")
    expect(!both.hasFastBrain, "groq+openai: sin cerebro rápido")

    let alone = VoiceStackResolver.resolve(
        secrets: [.groq: true],
        appleSpeech: true,
        localModel: nil)
    expect(alone.brain == nil, "solo groq: sin cerebro")
    expect(alone.mouth == nil, "solo groq: sin boca")
    expectEq(alone.ear, VoiceRole(id: "apple-analyzer", provider: "apple"),
             "solo groq: el oído es Apple")
    expect(!VoiceStack(brain: VoiceRole(id: "openai/gpt-oss-120b", provider: "groq")).hasFastBrain,
           "groq ya no cuenta como cerebro rápido")
}

/// 15e-2: `rememberStack` no longer reads the Groq key at press.
@MainActor func testAPressWithAStoredGroqKeyStillPicksOpenAIMini() async {
    let h = makeVoiceHarness(key: "sk-test")
    h.secrets.values[.groq] = "gsk-test"
    await h.session.hold()
    let stack = await h.session.lastStack
    expectEq(stack?.brain, VoiceRole(id: "gpt-4o-mini", provider: "openai"),
             "press: con clave Groq guardada, el cerebro sigue OpenAI mini")
}

@MainActor func testOpenAIFillsEveryRole() {
    let stack = VoiceStackResolver.resolve(
        secrets: [.openAI: true],
        appleSpeech: true,
        localModel: "qwen3:14b")
    // L4 (code review 2026-09-24): since 15e the hold's ear is always
    // Apple's analyzer; an OpenAI key no longer changes it.
    expectEq(stack.ear, VoiceRole(id: "apple-analyzer", provider: "apple"),
             "openai: el oído del hold sigue siendo Apple")
    expectEq(stack.brain, VoiceRole(id: "gpt-4o-mini", provider: "openai"),
             "openai: cerebro mini, no el gpt-4o del chat")
    expectEq(stack.mouth, VoiceRole(id: "gpt-4o-mini-tts", provider: "openai"),
             "openai: boca mini-tts")
    expectEq(stack.sight, VoiceRole(id: "gpt-4o-mini", provider: "openai"),
             "openai: vista mini")
}

@MainActor func testOllamaIsTheBrainWhenNothingElseIsPresent() {
    let stack = VoiceStackResolver.resolve(
        secrets: [:],
        appleSpeech: true,
        localModel: "qwen3:14b")
    expectEq(stack.brain, VoiceRole(id: "qwen3:14b", provider: "ollama"),
             "ollama: cerebro = el tag local")
    expectEq(stack.mouth, VoiceRole(id: "avspeech", provider: "apple"),
             "ollama: boca del sistema")
}

@MainActor func testNothingYieldsEmptyRoles() {
    let stack = VoiceStackResolver.resolve(
        secrets: [:],
        appleSpeech: false,
        localModel: nil)
    expect(stack.ear == nil, "vacío: sin oído inventado")
    expect(stack.brain == nil, "vacío: sin cerebro inventado")
    expect(stack.mouth == nil, "vacío: sin boca inventada")
    expect(stack.sight == nil, "vacío: sin vista inventada")
}

@MainActor func testTheChatPickerIsNotAnInput() {
    let secrets: [SecretKey: Bool] = [.openAI: true, .cerebras: true]
    let a = VoiceStackResolver.resolve(
        secrets: secrets, appleSpeech: true, localModel: "qwen3:14b")
    let b = VoiceStackResolver.resolve(
        secrets: secrets, appleSpeech: true, localModel: "llama3.2:3b")
    expectEq(a, b, "picker: el tag local no mueve un stack con OpenAI")
    expectEq(a.brain?.id, ProviderDescriptor.cerebras.model,
             "picker: providerOrder no es argumento del resolver")
}

@MainActor func testAHoldStackIgnoresTheChatPicker() async {
    let provider = TestConfigProvider(config: Config(
        chat: ChatSettings(providerOrder: ["ollama", "openrouter"])))
    let h = makeVoiceHarnessWithProvider(provider)
    await h.session.hold()
    let stack = await h.session.lastStack
    expectEq(stack?.brain?.id, "gpt-4o-mini",
             "hold: el desplegable ollama no cambia el cerebro")
    expectEq(stack?.ear?.id, "apple-analyzer",
             "hold: oído de producto, no el picker")
    expectEq(h.watch.latest.pipeline, .classic,
             "hold: 14b el hold es el camino de texto")
}
