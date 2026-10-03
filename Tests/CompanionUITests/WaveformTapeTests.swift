@testable import CompanionUI
import CompanionCore
import Testing

// The view's own tape: what the strip draws once VoiceLevelWaveform has fed it,
// without a window or wall time. The view feeds it two ways: onChange when the
// meter moves (`ingest`), and every timeline tick with the meter it holds
// (`frame`), because a meter that stops moving never reaches onChange.

/// One mic frame (2048 frames at 24 kHz, MicCapture's tap).
private let frameSeconds = 0.085
@MainActor private let width = Double(VoiceLevelWaveformMetrics.maxWidth)

@MainActor private func isBar(_ sample: Double) -> Bool {
    WaveformHistory.column(sample, gate: WaveformHistory.gate, height: Double(VoiceLevelWaveformMetrics.height)) != .dot
}

/// Ticks a held meter for `seconds`, as the timeline does when onChange stays
/// quiet; returns the live column's sample at every tick.
@MainActor private func hold(_ meter: Double, on tape: WaveformTape, from start: Double, seconds: Double,
                             scrolls: Bool) -> [Double] {
    let step = scrolls ? VoiceLevelWaveformMetrics.frameInterval : VoiceLevelWaveformMetrics.settleInterval
    let ticks = Int((seconds / step).rounded())
    return (0 ... ticks).map { index in
        tape.frame(meter: meter, now: start + Double(index) * step, width: width, scrolls: scrolls).last?.sample ?? -1
    }
}

@Test @MainActor func theTapeTurnsRoomNoiseIntoDotsAndSpeechIntoABar() {
    let tape = WaveformTape()
    var time = 0.0
    for _ in 0 ..< 30 {
        tape.ingest(meter: 0.12, at: time)
        tape.history.advance(elapsed: frameSeconds, width: width)
        time += frameSeconds
    }
    #expect(!tape.history.samples.isEmpty)
    #expect(tape.history.samples.allSatisfy { $0 == 0 }, "room noise is dots: \(tape.history.samples)")
    tape.ingest(meter: 0.45, at: time)
    #expect(isBar(tape.frame(meter: 0.45, now: time, width: width, scrolls: true).last?.sample ?? 0),
            "speech is a bar on its first frame")
}

// MicCapture clips at 1.0, so loud speech repeats 1.0 and onChange skips it.
@Test(arguments: [true, false])
@MainActor func clippedSpeechHeldAtOneDrawsBarsThroughout(scrolls: Bool) {
    let tape = WaveformTape()
    tape.ingest(meter: 1, at: 0)
    let live = hold(1, on: tape, from: 0, seconds: 1, scrolls: scrolls)
    #expect(live.allSatisfy(isBar), "live column: \(live)")
    if scrolls {
        #expect(tape.history.samples.count >= 10)
        #expect(tape.history.samples.allSatisfy(isBar), "every column of the clipped run: \(tape.history.samples)")
    }
}

@Test(arguments: [true, false])
@MainActor func aHeldRoomFloorStaysDots(scrolls: Bool) {
    let tape = WaveformTape()
    tape.ingest(meter: 0.12, at: 0)
    let live = hold(0.12, on: tape, from: 0, seconds: 1, scrolls: scrolls)
    #expect(live.allSatisfy { $0 == 0 }, "live column: \(live)")
    #expect(tape.history.samples.allSatisfy { $0 == 0 }, "\(tape.history.samples)")
}

@Test(arguments: [true, false])
@MainActor func voiceThenAStoppedMeterIsADotAfterTheHangover(scrolls: Bool) {
    let tape = WaveformTape()
    tape.ingest(meter: 0.5, at: 0)
    tape.ingest(meter: 0, at: 0.1)
    let live = hold(0, on: tape, from: 0.1, seconds: 0.6, scrolls: scrolls)
    #expect(live.last == 0, "live column: \(live)")
    if scrolls {
        #expect(tape.history.samples.suffix(3).allSatisfy { $0 == 0 }, "\(tape.history.samples)")
    }
}

@Test(arguments: [true, false])
@MainActor func aFrameSeenByTheTickAndByOnChangeCountsOnce(scrolls: Bool) {
    // The same script twice; in the second, onChange also delivers every frame
    // at the tick's instant, into the column the tick just fed.
    let meters = [0.12, 0.13, 0.5, 0.8, 0.8, 0.3, 0.12, 0.11, 0.12, 0.6, 0.12, 0.12, 0.12, 0.12]
    let once = WaveformTape()
    let twice = WaveformTape()
    var liveOnce: [Double] = []
    var liveTwice: [Double] = []
    for (index, meter) in meters.enumerated() {
        let now = Double(index) * frameSeconds
        liveOnce.append(once.frame(meter: meter, now: now, width: width, scrolls: scrolls).last?.sample ?? -1)
        _ = twice.frame(meter: meter, now: now, width: width, scrolls: scrolls)
        twice.ingest(meter: meter, at: now)
        liveTwice.append(twice.history.marks(width: width, scrolls: scrolls).last?.sample ?? -1)
    }
    #expect(liveOnce == liveTwice)
    #expect(once.history.samples == twice.history.samples)
    #expect(once.history.reference == twice.history.reference)
}
