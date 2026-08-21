import CompanionCore
import Testing

@Test @MainActor func voiceTapActionTests() {
    // When idle, tap should start voice.
    expectEq(VoiceTapAction.forState(.idle), .start,
             "idle: tap should start")

    // When error, tap should start voice (retry).
    expectEq(VoiceTapAction.forState(.error), .start,
             "error: tap should start (retry)")

    // When connecting, tap should hang up.
    expectEq(VoiceTapAction.forState(.connecting), .hangUp,
             "connecting: tap should hang up")

    // When listening, tap should hang up.
    expectEq(VoiceTapAction.forState(.listening), .hangUp,
             "listening: tap should hang up")

    // When thinking, tap should hang up.
    expectEq(VoiceTapAction.forState(.thinking), .hangUp,
             "thinking: tap should hang up")

    // When speaking, tap should interrupt (advance).
    expectEq(VoiceTapAction.forState(.speaking), .interrupt,
             "speaking: tap should interrupt (advance)")
}

@Test @MainActor func voiceTapLabelTests() {
    // Label should reflect the action that will happen.
    expectEq(VoiceTapAction.label(forState: .idle), "Hablar",
             "idle: label should be 'Hablar'")

    expectEq(VoiceTapAction.label(forState: .error), "Hablar",
             "error: label should be 'Hablar'")

    expectEq(VoiceTapAction.label(forState: .connecting), "Colgar",
             "connecting: label should be 'Colgar'")

    expectEq(VoiceTapAction.label(forState: .listening), "Colgar",
             "listening: label should be 'Colgar'")

    expectEq(VoiceTapAction.label(forState: .thinking), "Colgar",
             "thinking: label should be 'Colgar'")

    expectEq(VoiceTapAction.label(forState: .speaking), "Interrumpir",
             "speaking: label should be 'Interrumpir'")
}
