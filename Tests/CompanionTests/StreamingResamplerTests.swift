@preconcurrency import AVFoundation
@testable import CompanionServices
import Foundation
import Testing

// Revisión 2026-09-24 (L5): `finish()` cerraba la entrada del analyzer sin
// vaciar el conversor; lo que el filtro del resampler retenía — el final de
// la última sílaba — nunca llegaba al modelo.

@Test func streamingResamplerTests() {
    testDrainHandsOverWhatTheFilterHeld()
}

func testDrainHandsOverWhatTheFilterHeld() {
    guard let source = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true),
        let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
        let resampler = StreamingResampler(from: source, to: target),
        let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 2_400)
    else {
        expect(false, "L5: formatos del test")
        return
    }
    input.frameLength = 2_400
    if let samples = input.int16ChannelData?[0] {
        for i in 0 ..< 2_400 {
            samples[i] = Int16(8_000 * sin(Double(i) * 2 * .pi * 440 / 24_000))
        }
    }
    let converted = resampler.convert(input)?.frameLength ?? 0
    let drained = resampler.drain()?.frameLength ?? 0
    expect(drained > 0, "L5: el vaciado entrega lo retenido")
    let total = Int(converted + drained)
    expect(abs(total - 1_600) <= 2, "L5: 100 ms a 16 kHz, completos — got \(total)")
}
