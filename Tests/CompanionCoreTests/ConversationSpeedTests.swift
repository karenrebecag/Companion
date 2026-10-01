import CompanionCore
import Foundation
import Testing

// Spec velocidad-de-voz-por-conversacion §5 (Core half): the factor, its
// per-provider clamp, the tool declaration and the copy the model reads.

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

@Test func conversationSpeedStartsAtBaseFactorOne() {
    #expect(ConversationSpeed.base.factor == 1.0)
    #expect(near(ConversationSpeed.base.speed(for: .openAITTS, base: 1.1), 1.1))
    #expect(!ConversationSpeed.base.isLimited(for: .openAITTS, base: 1.1))
}

@Test func realtimeClampsTo025Through15() {
    let fast = ConversationSpeed(factor: 1.3)
    #expect(near(fast.speed(for: .realtime, base: 1.0), 1.3))
    #expect(near(fast.speed(for: .realtime, base: 1.4), 1.5))
    #expect(fast.isLimited(for: .realtime, base: 1.4))
    #expect(near(ConversationSpeed(factor: 0.25).speed(for: .realtime, base: 0.5), 0.25))
    #expect(ConversationSpeed(factor: 0.25).isLimited(for: .realtime, base: 0.5))
    #expect(!fast.isLimited(for: .realtime, base: 1.0))
}

@Test func openAITTSClampsTo025Through40() {
    #expect(near(ConversationSpeed(factor: 1.3).speed(for: .openAITTS, base: 1.1), 1.43))
    #expect(near(ConversationSpeed(factor: 4.0).speed(for: .openAITTS, base: 1.1), 4.0))
    #expect(ConversationSpeed(factor: 4.0).isLimited(for: .openAITTS, base: 1.1))
    #expect(near(ConversationSpeed(factor: 0.25).speed(for: .openAITTS, base: 0.5), 0.25))
    #expect(ConversationSpeed(factor: 0.25).isLimited(for: .openAITTS, base: 0.5))
}

@Test func elevenLabsClampsTo07Through12() {
    #expect(near(ConversationSpeed(factor: 1.3).speed(for: .elevenLabs, base: 1.0), 1.2))
    #expect(ConversationSpeed(factor: 1.3).isLimited(for: .elevenLabs, base: 1.0))
    #expect(near(ConversationSpeed(factor: 0.5).speed(for: .elevenLabs, base: 1.0), 0.7))
    #expect(near(ConversationSpeed(factor: 0.8).speed(for: .elevenLabs, base: 1.0), 0.8))
    #expect(!ConversationSpeed(factor: 0.8).isLimited(for: .elevenLabs, base: 1.0))
}

@Test func factorQuantizesToFiveHundredths() {
    #expect(near(ConversationSpeed(factor: 1.43).factor, 1.45))
    #expect(near(ConversationSpeed(factor: 1.42).factor, 1.4))
    #expect(near(ConversationSpeed(factor: 100).factor, 4.0))
    #expect(near(ConversationSpeed(factor: 0.01).factor, 0.25))
    // Few distinct values keeps the phrase cache from fragmenting.
    #expect(ConversationSpeed(factor: 1.431).factor == ConversationSpeed(factor: 1.449).factor)
}

@Test func parseFactorRejectsBoolStringMissingNaNAndNonPositive() {
    #expect(near(ConversationSpeed.factor(fromArguments: ["factor": 1.3])?.factor ?? 0, 1.3))
    #expect(near(ConversationSpeed.factor(fromArguments: ["factor": 2])?.factor ?? 0, 2.0))
    #expect(ConversationSpeed.factor(fromArguments: ["factor": true]) == nil)
    #expect(ConversationSpeed.factor(fromArguments: ["factor": false]) == nil)
    #expect(ConversationSpeed.factor(fromArguments: ["factor": "1.3"]) == nil)
    #expect(ConversationSpeed.factor(fromArguments: [:]) == nil)
    #expect(ConversationSpeed.factor(fromArguments: ["factor": Double.nan]) == nil)
    #expect(ConversationSpeed.factor(fromArguments: ["factor": Double.infinity]) == nil)
    #expect(ConversationSpeed.factor(fromArguments: ["factor": 0]) == nil)
    #expect(ConversationSpeed.factor(fromArguments: ["factor": -1.2]) == nil)
    #expect(ConversationSpeed.factor(fromArguments: ["factor": NSNull()]) == nil)
}

@Test func setSpeechSpeedHasStableWireNameInBothLanguages() {
    for language in AppLanguage.allCases {
        #expect(ToolSpec.setSpeechSpeed(language, current: .base).name == "set_speech_speed")
    }
}

@Test func setSpeechSpeedDescriptionCarriesCurrentFactor() {
    // Values absent from the static text, so only interpolation can satisfy this.
    let en = ToolSpec.setSpeechSpeed(.en, current: ConversationSpeed(factor: 1.45))
    #expect(en.description.contains("1.45"))
    let es = ToolSpec.setSpeechSpeed(.es, current: ConversationSpeed(factor: 0.55))
    #expect(es.description.contains("0.55"))
    #expect(en.description != es.description)

    for language in AppLanguage.allCases {
        let base = ToolSpec.setSpeechSpeed(language, current: .base).description
        #expect(base.contains("1.") == true)
        #expect(!base.contains("1.45") && !base.contains("0.55"))
        let moved = ToolSpec.setSpeechSpeed(language, current: ConversationSpeed(factor: 1.45)).description
        #expect(moved != base)
    }
}

@Test(arguments: AppLanguage.allCases)
func setSpeechSpeedEncodesStrictForChat(language: AppLanguage) throws {
    let spec = ToolSpec.setSpeechSpeed(language, current: .base)
    #expect(spec.required == ["factor"])
    #expect(spec.properties.map(\.name) == ["factor"])
    #expect(spec.properties.first?.type == "number")

    let chat = try #require(jsonDictionary(spec.encodeChat(strict: true)))
    let function = try #require(chat["function"] as? [String: Any])
    #expect(function["strict"] as? Bool == true)
    let parameters = try #require(function["parameters"] as? [String: Any])
    #expect(parameters["additionalProperties"] as? Bool == false)
    #expect(parameters["required"] as? [String] == ["factor"])
}

@Test func toolOutputNamesAppliedValueLimitAndOneShortPhrase() {
    let plain = SpeechSpeedCopy.toolOutput(applied: 1.3, limited: false, language: .en)
    #expect(plain.contains("1.3"))
    #expect(plain.lowercased().contains("one short phrase"))
    #expect(!plain.lowercased().contains("limited"))

    let capped = SpeechSpeedCopy.toolOutput(applied: 1.2, limited: true, language: .en)
    #expect(capped.contains("1.2"))
    #expect(capped.lowercased().contains("limited"))
    #expect(capped.lowercased().contains("one short phrase"))

    let es = SpeechSpeedCopy.toolOutput(applied: 1.3, limited: false, language: .es)
    #expect(es.contains("1.3"))
    #expect(es.lowercased().contains("frase corta"))
    #expect(!es.lowercased().contains("limitada"))
    let esCapped = SpeechSpeedCopy.toolOutput(applied: 1.2, limited: true, language: .es)
    #expect(esCapped.contains("1.2"))
    #expect(esCapped.lowercased().contains("limitada"))
    #expect(es != plain)

    #expect(SpeechSpeedCopy.label(1.0) == "1")
    #expect(SpeechSpeedCopy.label(1.45) == "1.45")

    #expect(SpeechSpeedCopy.confirmation(.es) == "Listo, ¿así?")
    #expect(SpeechSpeedCopy.confirmation(.en) == "Done. Like this?")
}

@Test func pacingNoteIsNilAtBase() {
    for language in AppLanguage.allCases {
        #expect(SpeechSpeedCopy.pacingNote(.base, language: language) == nil)
        // 1.02 quantizes to the base, so there is nothing to tell the model.
        #expect(SpeechSpeedCopy.pacingNote(ConversationSpeed(factor: 1.02), language: language) == nil)
    }
}

@Test func pacingNoteStatesDirectionAndNumberPerLanguage() throws {
    let fast = ConversationSpeed(factor: 1.3)
    let slow = ConversationSpeed(factor: 0.8)

    let enFast = try #require(SpeechSpeedCopy.pacingNote(fast, language: .en))
    let enSlow = try #require(SpeechSpeedCopy.pacingNote(slow, language: .en))
    #expect(enFast.contains("faster") && enFast.contains("1.3"))
    #expect(enSlow.contains("slower") && enSlow.contains("0.8"))
    #expect(!enFast.contains("slower") && !enSlow.contains("faster"))

    let esFast = try #require(SpeechSpeedCopy.pacingNote(fast, language: .es))
    let esSlow = try #require(SpeechSpeedCopy.pacingNote(slow, language: .es))
    #expect(esFast.contains("rápido") && esFast.contains("1.3"))
    #expect(esSlow.contains("lento") && esSlow.contains("0.8"))
    #expect(!esFast.contains("lento") && !esSlow.contains("rápido"))

    #expect(enFast != esFast)
    #expect(enSlow != esSlow)
}

@Test func provider_edges_table() {
    struct Row: Sendable {
        let provider: SpeechSpeedProvider
        let base: Double
        let factor: Double
        let speed: Double
        let limited: Bool
    }
    let rows: [Row] = [
        // Realtime, upper edge, one step either side, far outside.
        Row(provider: .realtime, base: 1.0, factor: 1.5, speed: 1.5, limited: false),
        Row(provider: .realtime, base: 1.0, factor: 1.45, speed: 1.45, limited: false),
        Row(provider: .realtime, base: 1.0, factor: 1.55, speed: 1.5, limited: true),
        Row(provider: .realtime, base: 1.0, factor: 4.0, speed: 1.5, limited: true),
        // Realtime, lower edge reached from above (base 0.5) and exactly.
        Row(provider: .realtime, base: 1.0, factor: 0.25, speed: 0.25, limited: false),
        Row(provider: .realtime, base: 0.5, factor: 0.5, speed: 0.25, limited: false),
        Row(provider: .realtime, base: 0.5, factor: 0.55, speed: 0.275, limited: false),
        Row(provider: .realtime, base: 0.5, factor: 0.45, speed: 0.25, limited: true),
        Row(provider: .realtime, base: 0.5, factor: 0.25, speed: 0.25, limited: true),
        // OpenAI TTS.
        Row(provider: .openAITTS, base: 1.0, factor: 4.0, speed: 4.0, limited: false),
        Row(provider: .openAITTS, base: 1.0, factor: 3.95, speed: 3.95, limited: false),
        Row(provider: .openAITTS, base: 1.1, factor: 4.0, speed: 4.0, limited: true),
        Row(provider: .openAITTS, base: 1.1, factor: 3.65, speed: 4.0, limited: true),
        Row(provider: .openAITTS, base: 1.0, factor: 0.25, speed: 0.25, limited: false),
        Row(provider: .openAITTS, base: 0.5, factor: 0.5, speed: 0.25, limited: false),
        Row(provider: .openAITTS, base: 0.5, factor: 0.45, speed: 0.25, limited: true),
        // ElevenLabs.
        Row(provider: .elevenLabs, base: 1.0, factor: 1.2, speed: 1.2, limited: false),
        Row(provider: .elevenLabs, base: 1.0, factor: 1.15, speed: 1.15, limited: false),
        Row(provider: .elevenLabs, base: 1.0, factor: 1.25, speed: 1.2, limited: true),
        Row(provider: .elevenLabs, base: 1.0, factor: 4.0, speed: 1.2, limited: true),
        Row(provider: .elevenLabs, base: 1.0, factor: 0.7, speed: 0.7, limited: false),
        Row(provider: .elevenLabs, base: 1.0, factor: 0.75, speed: 0.75, limited: false),
        Row(provider: .elevenLabs, base: 1.0, factor: 0.65, speed: 0.7, limited: true),
        Row(provider: .elevenLabs, base: 1.0, factor: 0.25, speed: 0.7, limited: true),
    ]
    for row in rows {
        let speed = ConversationSpeed(factor: row.factor)
        let label = "\(row.provider) base \(row.base) factor \(row.factor)"
        #expect(near(speed.speed(for: row.provider, base: row.base), row.speed), "\(label) speed")
        #expect(speed.isLimited(for: row.provider, base: row.base) == row.limited, "\(label) limited")
    }
}

@Test func quantizationMidpointsAndClampEdges() {
    // Half a step rounds away from zero: 1.425 is the documented direction.
    #expect(near(ConversationSpeed(factor: 1.425).factor, 1.45))
    #expect(near(ConversationSpeed(factor: 3.99).factor, 4.0))
    #expect(near(ConversationSpeed(factor: 0.26).factor, 0.25))
    #expect(near(ConversationSpeed(factor: 4.0).factor, 4.0))
    #expect(near(ConversationSpeed(factor: 0.25).factor, 0.25))
}

@Test func initFallsBackToBaseForNonFiniteAndClampsNonPositive() {
    #expect(ConversationSpeed(factor: .nan) == .base)
    #expect(ConversationSpeed(factor: .infinity) == .base)
    #expect(ConversationSpeed(factor: -.infinity) == .base)
    #expect(near(ConversationSpeed(factor: 0).factor, 0.25))
    #expect(near(ConversationSpeed(factor: -1).factor, 0.25))
}

@Test func parseFactorFromRealJSON() throws {
    func parse(_ json: String) throws -> ConversationSpeed? {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        return ConversationSpeed.factor(fromArguments: try #require(object))
    }
    #expect(try parse(#"{"factor":true}"#) == nil)
    #expect(try parse(#"{"factor":false}"#) == nil)
    #expect(try parse(#"{"factor":0}"#) == nil)
    #expect(try parse(#"{"factor":-0.0}"#) == nil)
    #expect(try parse(#"{"factor":-2}"#) == nil)
    #expect(try parse(#"{"factor":"1.3"}"#) == nil)
    #expect(try parse(#"{"factor":null}"#) == nil)
    let one = try #require(try parse(#"{"factor":1}"#))
    let fast = try #require(try parse(#"{"factor":1.3}"#))
    let tiny = try #require(try parse(#"{"factor":1e-9}"#))
    let huge = try #require(try parse(#"{"factor":1e308}"#))
    #expect(near(one.factor, 1.0))
    #expect(near(fast.factor, 1.3))
    #expect(near(tiny.factor, 0.25))
    #expect(near(huge.factor, 4.0))
}

@Test func parseFactorAcceptsIntAndFloatNumbers() {
    #expect(near(ConversationSpeed.factor(fromArguments: ["factor": NSNumber(value: 2)])?.factor ?? 0, 2.0))
    #expect(near(ConversationSpeed.factor(fromArguments: ["factor": NSNumber(value: Float(1.3))])?.factor ?? 0, 1.3))
    #expect(ConversationSpeed.factor(fromArguments: ["factor": NSNumber(value: Float.nan)]) == nil)
}

private func jsonDictionary(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}
