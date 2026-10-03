import CompanionCore
import Testing

// Waveform VAD brief (docs/research/waveform-vad-voiced.md, section 5 and the
// checklist): room noise at the measured 0.12 floor must stop drawing bars,
// speech must start a bar on its first frame, and the end of speech must turn
// into dots once the hangover runs out.

/// One mic frame of ~85 ms (2048 frames at 24 kHz, MicCapture's tap).
private let frameSeconds = 0.085

/// #expect cannot expand a mutating call on its receiver; a free function can.
private func feed(_ gate: inout VoiceActivityGate, _ meter: Double, at time: Double) -> Bool {
    gate.voiced(meter: meter, at: time)
}

/// Feeds the same frame at a steady cadence and returns every verdict.
private func verdicts(_ meter: Double, seconds: Double, into gate: inout VoiceActivityGate,
                      from start: Double = 0) -> [Bool] {
    stride(from: start, to: start + seconds, by: frameSeconds).map { gate.voiced(meter: meter, at: $0) }
}

@Suite struct VoiceActivityGateNoiseTests {
    @Test(arguments: [0.0, 0.05, 0.12, 0.149])
    func aSustainedRoomFloorIsNeverVoice(meter: Double) {
        var gate = VoiceActivityGate()
        #expect(!verdicts(meter, seconds: 5, into: &gate).contains(true))
    }

    @Test func thirtyColumnsOfRoomNoiseAreAllDots() {
        var gate = VoiceActivityGate()
        var history = WaveformHistory()
        let column = WaveformHistory.columnStep / WaveformHistory.pointsPerSecond
        var time = 0.0
        for index in 0 ..< 30 {
            // The floor jitters around 0.12, as a real mic does.
            let meter = index.isMultiple(of: 2) ? 0.11 : 0.13
            history.ingest(level: WaveformHistory.level(meter: meter), voiced: gate.voiced(meter: meter, at: time))
            history.advance(elapsed: column, width: 1000)
            time += column
        }
        #expect(history.samples.count == 30)
        #expect(history.samples.allSatisfy { $0 == 0 }, "\(history.samples)")
        let drawn = history.samples.map { WaveformHistory.column($0, gate: WaveformHistory.gate, height: 26) }
        #expect(drawn.allSatisfy { $0 == .dot })
    }
}

@Suite struct VoiceActivityGateThresholdTests {
    @Test func speechOpensOnItsFirstFrame() {
        var gate = VoiceActivityGate()
        #expect(!feed(&gate, 0.12, at: 0))
        #expect(feed(&gate, 0.3, at: frameSeconds), "attack is one frame")
    }

    @Test func theOpenLevelItselfOpens() {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, VoiceActivityGate.openLevel, at: 0))
    }

    @Test func betweenTheLevelsAClosedGateStaysClosed() {
        var gate = VoiceActivityGate()
        #expect(!feed(&gate, 0.17, at: 0))
        #expect(!feed(&gate, 0.17, at: 1), "0.17 without an opening is still the floor")
    }

    @Test func betweenTheLevelsAnOpenGateStaysOpen() {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.3, at: 0))
        // Well past the hangover: only hysteresis can keep it open.
        #expect(verdicts(0.17, seconds: 2, into: &gate, from: frameSeconds).allSatisfy { $0 })
    }

    @Test func theLevelsAreTheBriefs() {
        #expect(VoiceActivityGate.openLevel == 0.20)
        #expect(VoiceActivityGate.openLevel == HoldAudioBuffer.speechRMSThreshold, "one measured voice line, not a fourth")
        #expect(VoiceActivityGate.closeLevel == 0.15)
        #expect(VoiceActivityGate.hangover == 0.20)
    }
}

@Suite struct VoiceActivityGateHangoverTests {
    @Test(arguments: [(0.19, true), (0.21, false)])
    func voiceOutlivesItsLastFrameByTheHangover(after: Double, voiced: Bool) {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 10))
        #expect(feed(&gate, 0.12, at: 10 + after) == voiced)
    }

    @Test func aVoicedFrameRearmsTheHangover() {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 0))
        #expect(feed(&gate, 0.12, at: 0.05))
        #expect(feed(&gate, 0.4, at: 0.1))
        #expect(feed(&gate, 0.12, at: 0.29), "0.19 s after the re-arming frame, not 0.29 after the first")
        #expect(!feed(&gate, 0.12, at: 0.31))
    }

    @Test func onceClosedTheFloorDoesNotReopen() {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 0))
        #expect(!feed(&gate, 0.12, at: 0.3))
        #expect(!feed(&gate, 0.17, at: 0.4), "closed again, so 0.17 is under the open level")
    }
}

@Suite struct VoiceActivityGateRobustnessTests {
    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func aBrokenLevelIsNotVoice(meter: Double) {
        var gate = VoiceActivityGate()
        #expect(!feed(&gate, meter, at: 0))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func aBrokenLevelDoesNotHoldTheGateOpen(meter: Double) {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 0))
        // A broken frame is a quiet one: it neither re-arms nor outlives the hangover.
        let after = verdicts(meter, seconds: 1, into: &gate, from: frameSeconds)
        #expect(after.first == true, "still inside the hangover")
        #expect(after.last == false, "\(after)")
        #expect(!feed(&gate, 0.12, at: 2))
    }

    @Test(arguments: [-100.0, 9.0])
    func aClockGoingBackwardsDoesNotHoldTheGateOpen(back: Double) {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 10))
        // Backwards, the elapsed time is unknown: a frame under the close
        // level ends the voice instead of waiting for the clock to catch up.
        #expect(!feed(&gate, 0.12, at: back))
        #expect(!feed(&gate, 0.12, at: back + frameSeconds))
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func aBrokenClockDoesNotHoldTheGateOpen(time: Double) {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: time), "a loud frame is voice whatever the clock says")
        #expect(!feed(&gate, 0.12, at: time))
        #expect(!feed(&gate, 0.12, at: 1))
    }

    @Test func afterABackwardsJumpSpeechStillWorks() {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 10))
        #expect(feed(&gate, 0.5, at: 2))
        #expect(feed(&gate, 0.12, at: 2.1))
        #expect(!feed(&gate, 0.12, at: 2.3))
    }
}

@Suite struct VoiceActivityGateSpeechTests {
    @Test func aSentenceDrawsBarsWhereItSpeaksAndDotsPastTheHangover() {
        // 0.3-0.8 speech with 0.12 gaps, each value one ~85 ms frame.
        let meters = [0.12, 0.12, 0.12, 0.45, 0.7, 0.3, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12,
                      0.8, 0.5, 0.35, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12]
        var gate = VoiceActivityGate()
        var history = WaveformHistory()
        var lastVoice = -Double.infinity
        var spokeInColumn = false
        var allPastHangover = true
        var expected: [(spoke: Bool, quiet: Bool)] = []
        for (index, meter) in meters.enumerated() {
            let time = Double(index) * frameSeconds
            if meter >= VoiceActivityGate.openLevel { lastVoice = time }
            spokeInColumn = spokeInColumn || meter >= VoiceActivityGate.openLevel
            allPastHangover = allPastHangover && time - lastVoice > VoiceActivityGate.hangover
            history.ingest(level: WaveformHistory.level(meter: meter), voiced: gate.voiced(meter: meter, at: time))
            let before = history.samples.count
            history.advance(elapsed: frameSeconds, width: 1000)
            for _ in before ..< history.samples.count {
                expected.append((spokeInColumn, allPastHangover))
                spokeInColumn = false
                allPastHangover = true
            }
        }
        #expect(expected.count == history.samples.count)
        #expect(expected.contains { $0.spoke } && expected.contains { $0.quiet }, "the script has both kinds")
        for (sample, column) in zip(history.samples, expected) {
            let drawn = WaveformHistory.column(sample, gate: WaveformHistory.gate, height: 26)
            if column.spoke {
                #expect(drawn != .dot, "a column with speech is a bar")
            }
            if column.quiet {
                #expect(drawn == .dot, "a column past the hangover is a dot")
            }
        }
    }
}

@Suite struct VoiceActivityGateBoundaryTests {
    @Test func exactlyTheHangoverAfterTheLastVoiceIsClosed() {
        // 0 and the constant itself, so the difference is the constant bit for bit.
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 0))
        #expect(!gate.isVoiced(at: VoiceActivityGate.hangover))
        #expect(!feed(&gate, 0.12, at: VoiceActivityGate.hangover))
    }

    @Test func exactlyTheCloseLevelKeepsAnOpenGateOpen() {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 0))
        let held = verdicts(VoiceActivityGate.closeLevel, seconds: 0.5, into: &gate, from: frameSeconds)
        #expect(held.count > 3 && held.allSatisfy { $0 }, "\(held)")
    }
}

// The view only feeds the gate when the meter changes, so a meter that stops
// (the mic ends, or digital silence sits at exactly 0) must still let the
// voice end when the clock passes the hangover.
@Suite struct VoiceActivityGateClockTests {
    @Test func withoutFramesTheHangoverExpiresWithTheClock() {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 0))
        #expect(feed(&gate, 0.0, at: 0.1), "still inside the hangover")
        #expect(gate.isVoiced(at: 0.19))
        #expect(!gate.isVoiced(at: 0.5))
    }

    @Test func aRepeatedVoiceStaysVoicedThenExpiresWhenItStops() {
        var gate = VoiceActivityGate()
        let held = verdicts(0.5, seconds: 2, into: &gate)
        #expect(held.allSatisfy { $0 })
        let last = Double(held.count - 1) * frameSeconds
        #expect(gate.isVoiced(at: last + 0.1))
        #expect(!gate.isVoiced(at: last + 0.3))
    }

    @Test func aRepeatedFloorIsNeverVoiced() {
        var gate = VoiceActivityGate()
        _ = verdicts(0.12, seconds: 2, into: &gate)
        #expect(!gate.isVoiced(at: 2))
    }

    @Test(arguments: [Double.nan, .infinity, -1])
    func aBrokenOrBackwardsClockIsNotVoice(time: Double) {
        var gate = VoiceActivityGate()
        #expect(feed(&gate, 0.5, at: 0))
        #expect(!gate.isVoiced(at: time))
    }
}
