import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 15c-2 (TDD row 5). A hold's own PCM, capped so a runaway hold never
// grows without bound (wave-15c §8). Since 15e the PCM only feeds the ear
// what it missed while starting; the hold itself keeps energy, not audio.

@Test @MainActor func holdAudioBufferTests() {
    testFramesAccumulateInOrder()
    testA90sHoldSendsOnly60s()
    testResetClearsThePreviousHold()
    testAnEmptyFrameDoesNotCrash()
    testSilentFramesHaveNoSpeechEnergy()
    testLoudFramesHaveSpeechEnergy()
    testASingleSpikeIsNotSpeech()
    testResetClearsTheSpeechFlagToo()
    testTheHoldEnergyGateKeepsNoAudio()
}

/// 15e-4: with the cloud ear gone nothing reads the hold's own PCM at release — only
/// its energy — so the runtime's gate must not sit on up to 60 s of audio.
@MainActor func testTheHoldEnergyGateKeepsNoAudio() {
    let runtime = ClassicRuntime(
        transcriber: FakeTranscriber(), synthesizer: ScriptedSynth(),
        chat: ScriptedChat(), thread: ScriptedThread())
    for _ in 0..<5 {
        runtime.holdAudio.hearLive(MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.4))
    }
    expect(runtime.holdAudio.hasSpeech, "gate: la energía sí se mide")
    expectEq(runtime.holdAudio.keptBytes, 0, "gate: el audio del hold no se guarda")
}

/// Live bug (HIGH, 2026-09-23): Karen held FN without speaking; every frame
/// stayed near the mic's own noise floor (0.12) and the cloud ear still
/// hallucinated text. The buffer itself must say "no speech" so
/// `ClassicRuntime` names a silent hold as silence.
@MainActor func testSilentFramesHaveNoSpeechEnergy() {
    var buffer = HoldAudioBuffer()
    for _ in 0..<10 {
        buffer.append(MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.1))
    }
    expect(!buffer.hasSpeech, "buffer: RMS bajo el piso de ruido no es voz")
}

@MainActor func testLoudFramesHaveSpeechEnergy() {
    var buffer = HoldAudioBuffer()
    for _ in 0..<5 {
        buffer.append(MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.4))
    }
    expect(buffer.hasSpeech, "buffer: varios frames por encima del umbral sí es voz")
}

/// A single loud frame (a click, a chair creak) must not pass the gate.
@MainActor func testASingleSpikeIsNotSpeech() {
    var buffer = HoldAudioBuffer()
    buffer.append(MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.1))
    buffer.append(MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.9))
    buffer.append(MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.1))
    expect(!buffer.hasSpeech, "buffer: un solo pico no cuenta como voz")
}

@MainActor func testResetClearsTheSpeechFlagToo() {
    var buffer = HoldAudioBuffer()
    for _ in 0..<5 {
        buffer.append(MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.4))
    }
    buffer.reset()
    expect(!buffer.hasSpeech, "buffer: reset también limpia la bandera de voz")
}

@MainActor func testFramesAccumulateInOrder() {
    var buffer = HoldAudioBuffer()
    buffer.append(MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.1))
    buffer.append(MicFrame(pcm16le24k: Data([0x03, 0x04]), rms: 0.1))
    expectEq(buffer.snapshot, Data([0x01, 0x02, 0x03, 0x04]),
             "buffer: los frames se concatenan en orden")
}

/// 90 s of 24 kHz mono 16-bit audio, fed one second at a time — the
/// snapshot must stop growing at 60 s worth of bytes.
@MainActor func testA90sHoldSendsOnly60s() {
    var buffer = HoldAudioBuffer(maxSeconds: 60, sampleRate: 24_000)
    let oneSecond = Data(repeating: 0xAB, count: 24_000 * 2)
    for _ in 0..<90 {
        buffer.append(MicFrame(pcm16le24k: oneSecond, rms: 0.1))
    }
    expectEq(buffer.snapshot.count, 60 * 24_000 * 2,
             "buffer: 90 s de hold, solo se quedan 60 s")
}

@MainActor func testResetClearsThePreviousHold() {
    var buffer = HoldAudioBuffer()
    buffer.append(MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.1))
    buffer.reset()
    expect(buffer.snapshot.isEmpty, "buffer: reset deja el hold siguiente en cero")
}

@MainActor func testAnEmptyFrameDoesNotCrash() {
    var buffer = HoldAudioBuffer()
    buffer.append(MicFrame(pcm16le24k: Data(), rms: 0))
    expect(buffer.snapshot.isEmpty, "buffer: un frame vacío no rompe nada")
}
