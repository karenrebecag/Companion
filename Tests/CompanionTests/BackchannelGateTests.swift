import CompanionCore
import Testing

@Test @MainActor func backchannelGateTests() {
    testShortAckDoesNotInterrupt()
    testSustainedSpeechInterrupts()
    testGapResetsTheRun()
    testOnceOpenNothingIsClipped()
    testResetGuardsTheNextReply()
}

/// The bug from the field: "ajá", "Mhm" and "OK" were cutting the agent off.
@MainActor func testShortAckDoesNotInterrupt() {
    var gate = BackchannelGate()
    // Three loud frames is roughly a quarter second: a grunt, not a sentence.
    for _ in 0 ..< 3 {
        expect(!gate.allowsWhileSpeaking(rms: 0.4),
               "backchannel: un asentimiento corto no interrumpe")
    }
}

@MainActor func testSustainedSpeechInterrupts() {
    var gate = BackchannelGate()
    var opened = false
    for _ in 0 ..< BackchannelGate.defaultRequiredFrames {
        opened = gate.allowsWhileSpeaking(rms: 0.4)
    }
    expect(opened, "backchannel: hablar sostenido SÍ interrumpe")
}

@MainActor func testGapResetsTheRun() {
    var gate = BackchannelGate()
    for _ in 0 ..< 4 { _ = gate.allowsWhileSpeaking(rms: 0.4) }
    _ = gate.allowsWhileSpeaking(rms: 0.01)
    for _ in 0 ..< 4 {
        expect(!gate.allowsWhileSpeaking(rms: 0.4),
               "backchannel: tres gruñidos sueltos no son una frase")
    }
}

@MainActor func testOnceOpenNothingIsClipped() {
    var gate = BackchannelGate()
    for _ in 0 ..< BackchannelGate.defaultRequiredFrames {
        _ = gate.allowsWhileSpeaking(rms: 0.4)
    }
    expect(gate.allowsWhileSpeaking(rms: 0.01),
           "backchannel: abierto deja pasar hasta las pausas de la frase")
}

@MainActor func testResetGuardsTheNextReply() {
    var gate = BackchannelGate()
    for _ in 0 ..< BackchannelGate.defaultRequiredFrames {
        _ = gate.allowsWhileSpeaking(rms: 0.4)
    }
    gate.reset()
    expect(!gate.allowsWhileSpeaking(rms: 0.4),
           "backchannel: la siguiente respuesta vuelve a estar protegida")
}
