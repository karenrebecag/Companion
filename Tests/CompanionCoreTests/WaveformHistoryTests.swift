import CompanionCore
import Testing

// Expected values are worked by hand from Incredible 0.2.36's island waveform
// (frontend-0.2.36/overlay-DstkIEbM.js, bytes 30654-31911), so a drifted
// constant shows up as a wrong number, not as a different picture.

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

private func voicedHistory(amplitude: Double, columns: Int, into history: inout WaveformHistory) {
    for _ in 0 ..< columns {
        history.ingest(level: WaveformHistory.level(amplitude: amplitude))
        history.advance(elapsed: WaveformHistory.columnStep / WaveformHistory.pointsPerSecond, width: 1000)
    }
}

@Suite struct WaveformHistoryScaleTests {
    @Test(arguments: [
        (1.0, 1.0),
        (0.0, 0.001),
        (0.5, 0.03162277660168379),
    ])
    func levelIsAPositionOnASixtyDecibelRange(level: Double, amplitude: Double) {
        #expect(close(WaveformHistory.amplitude(level: level), amplitude))
    }

    @Test(arguments: [
        (1.0, 1.0),
        (0.1, 0.6666666666666666),
        (0.008, 0.30102999566398125),
        (0.001, 0.0),
        (0.0, 0.0),
        (2.0, 1.0),
    ])
    func linearAmplitudeMapsOntoTheSameRange(amplitude: Double, level: Double) {
        #expect(close(WaveformHistory.level(amplitude: amplitude), level))
    }

    @Test func maxColumnsIsOnePerStep() {
        #expect(WaveformHistory.maxColumns(width: 180) == 36)
        #expect(WaveformHistory.maxColumns(width: 4.9) == 0)
        #expect(WaveformHistory.maxColumns(width: -10) == 0)
    }
}

@Suite struct WaveformHistoryVoiceTests {
    @Test func withoutAVoiceFlagTheGateDecides() {
        let history = WaveformHistory()
        #expect(!history.isVoiced(0.08), "the gate itself is silence")
        #expect(history.isVoiced(0.0801))
        #expect(!history.isVoiced(0))
    }

    @Test func onceAFlagArrivesItReplacesTheGate() {
        var history = WaveformHistory()
        history.ingest(level: 0.9, voiced: false)
        #expect(!history.isVoiced(0.9), "a loud frame the VAD calls noise is a dot")
        history.ingest(level: 0.01, voiced: true)
        #expect(history.isVoiced(0.01), "a quiet frame the VAD calls voice is a bar")
    }

    @Test func theFlagHoldsForTheColumnAndResetsAfterIt() {
        var history = WaveformHistory()
        history.ingest(level: 0.7, voiced: true)
        history.ingest(level: 0.7, voiced: false)
        #expect(history.isVoiced(0.7), "voice anywhere in a column makes it a bar")
        history.advance(elapsed: WaveformHistory.columnStep / WaveformHistory.pointsPerSecond, width: 100)
        #expect(!history.isVoiced(0.7), "the next column starts silent")
    }

    @Test func unvoicedSampleIsZero() {
        let history = WaveformHistory()
        #expect(history.sample(for: 0.05) == 0)
    }

    @Test(arguments: [
        (0.008, 0.1636363636363638),
        (0.04, 0.7482294581719431),
        (0.08, 1.0),
        (1.0, 1.0),
    ])
    func voicedSampleSitsInATwentyTwoDecibelWindowUnderThePeak(amplitude: Double, sample: Double) {
        let history = WaveformHistory()
        #expect(close(history.sample(for: WaveformHistory.level(amplitude: amplitude)), sample))
    }

    @Test func theLoudestFrameOfAColumnIsTheOneDrawn() {
        var history = WaveformHistory()
        history.ingest(level: 0.9)
        history.ingest(level: 0.1)
        #expect(history.current == 0.9)
        history.advance(elapsed: WaveformHistory.columnStep / WaveformHistory.pointsPerSecond, width: 100)
        #expect(history.current == 0.1, "after the column only the latest frame is left")
    }
}

@Suite struct WaveformHistoryGainTests {
    @Test func theReferenceStartsAtTheFloor() {
        #expect(WaveformHistory().reference == WaveformHistory.peakFloor)
    }

    @Test func theReferenceAtMostDoublesPerColumn() {
        var history = WaveformHistory()
        var references: [Double] = []
        for _ in 0 ..< 4 {
            voicedHistory(amplitude: 1, columns: 1, into: &history)
            references.append(history.reference)
        }
        #expect(zip(references, [0.16, 0.32, 0.64, 1.0]).allSatisfy { close($0, $1) }, "\(references)")
    }

    @Test func theColumnIsScaledAgainstTheUpdatedReference() {
        var history = WaveformHistory()
        voicedHistory(amplitude: 1, columns: 1, into: &history)
        voicedHistory(amplitude: 0.02, columns: 1, into: &history)
        // 0.16 decays to 0.15856 first, and the 0.02 column is measured
        // against that, not against the 0.16 it started from.
        #expect(close(history.reference, 0.15856))
        #expect(close(history.samples.last ?? -1, 0.24797222712814415))
    }

    @Test func silenceDecaysTheReferenceByTheColumn() {
        var history = WaveformHistory()
        voicedHistory(amplitude: 1, columns: 4, into: &history)
        #expect(close(history.reference, 1))
        history.ingest(level: 0)
        history.advance(elapsed: WaveformHistory.columnStep / WaveformHistory.pointsPerSecond, width: 1000)
        #expect(close(history.reference, 0.991))
        history.advance(elapsed: WaveformHistory.columnStep / WaveformHistory.pointsPerSecond, width: 1000)
        #expect(close(history.reference, 0.982081))
        #expect(history.samples.suffix(2) == [0, 0])
    }

    @Test func aQuietVoicedColumnAlsoDecays() {
        var history = WaveformHistory()
        voicedHistory(amplitude: 1, columns: 4, into: &history)
        voicedHistory(amplitude: 0.008, columns: 1, into: &history)
        #expect(close(history.reference, 0.991))
    }

    @Test func theReferenceNeverDropsUnderTheFloor() {
        var history = WaveformHistory()
        history.ingest(level: 0)
        history.advance(elapsed: 1, width: 1000)
        #expect(history.reference == WaveformHistory.peakFloor)
    }
}

@Suite struct WaveformHistoryScrollTests {
    @Test func aTenthOfASecondIsOneColumnAndSomeCarry() {
        var history = WaveformHistory()
        history.advance(elapsed: 0.1, width: 100)
        #expect(history.samples.count == 1)
        #expect(close(history.carry, 0.6))
    }

    @Test func aSecondIsElevenColumns() {
        var history = WaveformHistory()
        history.advance(elapsed: 1, width: 100)
        #expect(history.samples.count == 11)
        #expect(close(history.carry, 1))
    }

    @Test func noTimeNoColumn() {
        var history = WaveformHistory()
        history.advance(elapsed: 0, width: 100)
        #expect(history.samples.isEmpty)
        #expect(history.carry == 0)
    }

    @Test func historyIsBoundedByTheWidthAndDropsTheOldest() {
        var history = WaveformHistory()
        voicedHistory(amplitude: 1, columns: 6, into: &history)
        history.ingest(level: 0)
        for _ in 0 ..< 3 {
            history.advance(elapsed: WaveformHistory.columnStep / WaveformHistory.pointsPerSecond, width: 20)
        }
        #expect(history.samples == [1, 0, 0, 0])
    }

    @Test func aLongStallScrollsAtMostOneSecond() {
        var history = WaveformHistory()
        history.advance(elapsed: 3600, width: 10000)
        #expect(history.samples.count == 11)
    }
}

@Suite struct WaveformHistoryShapeTests {
    @Test(arguments: [
        (0.0, WaveformColumn.dot),
        (0.08, WaveformColumn.dot),
        (0.1, WaveformColumn.bar(height: 4.5)),
        (1.0, WaveformColumn.bar(height: 22)),
    ])
    func atOrUnderTheGateIsADot(sample: Double, column: WaveformColumn) {
        #expect(WaveformHistory.column(sample, gate: 0.08, height: 26) == column)
    }

    @Test(arguments: [
        (0.5, 11.297046709381117),
        (0.9, 19.950087375313558),
    ])
    func barHeightFollowsAGentleCurve(sample: Double, height: Double) {
        guard case .bar(let drawn) = WaveformHistory.column(sample, gate: 0.08, height: 26) else {
            Issue.record("expected a bar")
            return
        }
        #expect(close(drawn, height))
    }

    @Test func theNewestColumnSitsHalfAStepFromTheRightEdge() {
        #expect(WaveformHistory.headX(width: 100) == 97.5)
    }

    @Test func olderColumnsStepLeftAndSlideByTheCarry() {
        let still = (0 ..< 3).map { WaveformHistory.x(index: $0, count: 3, width: 100, carry: 0) }
        #expect(still == [87.5, 92.5, 97.5])
        let sliding = (0 ..< 3).map { WaveformHistory.x(index: $0, count: 3, width: 100, carry: 1.2) }
        #expect(zip(sliding, [86.3, 91.3, 96.3]).allSatisfy { close($0, $1) }, "\(sliding)")
    }
}

private let oneColumn = WaveformHistory.columnStep / WaveformHistory.pointsPerSecond

private func columns(_ count: Int, level: Double, voiced: Bool? = nil, width: Double = 1000,
                     into history: inout WaveformHistory) {
    for _ in 0 ..< count {
        history.ingest(level: level, voiced: voiced)
        history.advance(elapsed: oneColumn, width: width)
    }
}

private func inUnitRange(_ value: Double) -> Bool {
    value.isFinite && value >= 0 && value <= 1
}

@Suite struct WaveformHistoryRobustnessTests {
    @Test func aNaNFrameDoesNotFreezeTheScroll() {
        var history = WaveformHistory()
        history.advance(elapsed: .nan, width: 100)
        history.advance(elapsed: 0.1, width: 100)
        #expect(history.carry.isFinite)
        #expect(history.samples.count == 1)
    }

    @Test func anInfiniteFrameIsTheOneSecondCap() {
        var history = WaveformHistory()
        history.advance(elapsed: .infinity, width: 1000)
        #expect(history.samples.count == 11)
    }

    @Test(arguments: [-1.0, -Double.infinity])
    func negativeTimeScrollsNothing(elapsed: Double) {
        var history = WaveformHistory()
        history.advance(elapsed: elapsed, width: 100)
        #expect(history.samples.isEmpty)
        #expect(history.carry == 0)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 5])
    func aBrokenLevelStaysInRange(level: Double) {
        var history = WaveformHistory()
        columns(2, level: level, into: &history)
        history.ingest(level: level)
        #expect(inUnitRange(history.current))
        #expect(inUnitRange(history.sample(for: history.current)))
        #expect(inUnitRange(history.reference))
        #expect(history.samples.allSatisfy(inUnitRange), "\(history.samples)")
    }
}

@Suite struct WaveformHistoryMeterTests {
    // Companion's meter is RMS x 6 clipped at 1 (MicCapture.rms); Incredible's
    // level is a dBFS position, so the meter is undone before the dB mapping.
    @Test(arguments: [
        (0.1, 0.4072829165387855),
        (0.6, 0.6666666666666666),
        (1.0, 0.7406162498721187),
        (0.0, 0.0),
    ])
    func theMicMeterIsReadAsDecibelsOfTheTrueRMS(meter: Double, level: Double) {
        #expect(close(WaveformHistory.level(meter: meter), level))
    }
}

@Suite struct WaveformHistoryConstantTests {
    @Test func theConstantsAreIncredibles() {
        #expect(WaveformHistory.window == 22)
        #expect(WaveformHistory.peakFloor == 0.08)
        #expect(WaveformHistory.peakDecay == 0.991)
        #expect(WaveformHistory.peakGrowth == 2)
        #expect(WaveformHistory.columnStep == 5)
        #expect(WaveformHistory.pointsPerSecond == 56)
        #expect(WaveformHistory.barWidth == 2.5)
        #expect(WaveformHistory.gate == 0.08)
        #expect(WaveformHistory.decibelRange == 60)
    }

    @Test(arguments: [
        (0.1, 0.1),
        (0.16, 0.16),
        (0.2, 0.16),
    ])
    func theReferenceFollowsAVoiceUpToTwiceItself(amplitude: Double, reference: Double) {
        var history = WaveformHistory()
        columns(1, level: WaveformHistory.level(amplitude: amplitude), into: &history)
        #expect(close(history.reference, reference), "\(history.reference)")
    }

    @Test func justOverTheGateIsTheShortestBar() {
        #expect(WaveformHistory.column(0.0801, gate: 0.08, height: 26) == .bar(height: 4.5))
    }

    @Test(arguments: [1.0, 1.0001])
    func oneSecondIsTheLongestStep(elapsed: Double) {
        var history = WaveformHistory()
        history.advance(elapsed: elapsed, width: 1000)
        #expect(history.samples.count == 11)
        #expect(close(history.carry, 1))
    }
}

@Suite struct WaveformHistoryLongRunTests {
    @Test func aSpikeThenSilenceDecaysToTheFloor() {
        var history = WaveformHistory()
        voicedHistory(amplitude: 1, columns: 4, into: &history)
        columns(100, level: 0, into: &history)
        #expect(close(history.reference, 0.40491647601142666), "\(history.reference)")
        columns(200, level: 0, into: &history)
        #expect(history.reference == WaveformHistory.peakFloor)
    }

    @Test func longSilenceStaysFlatAndBounded() {
        var history = WaveformHistory()
        columns(2000, level: 0, into: &history)
        #expect(history.samples.allSatisfy { $0 == 0 })
        #expect(history.reference == WaveformHistory.peakFloor)
        #expect(history.samples.count <= WaveformHistory.maxColumns(width: 1000))
    }

    @Test func afterASpikeAVoiceIsMeasuredAgainstTheDecayedPeak() {
        var history = WaveformHistory()
        voicedHistory(amplitude: 1, columns: 4, into: &history)
        voicedHistory(amplitude: 0.2, columns: 1, into: &history)
        #expect(close(history.reference, 0.991))
        #expect(close(history.samples.last ?? -1, 0.4186907580767359))
    }

    @Test func aNarrowerStripKeepsTheNewestColumnsInOrder() {
        var history = WaveformHistory()
        // The peak climbs first, so the descending run below is measured against a settled peak.
        voicedHistory(amplitude: 1, columns: 4, into: &history)
        for step in 0 ..< 20 {
            columns(1, level: 1 - 0.02 * Double(step), into: &history)
        }
        let before = history.samples
        #expect(Set(before.suffix(20)).count == 20, "\(before)")
        columns(1, level: 0, width: 50, into: &history)
        #expect(history.samples == Array((before + [0]).suffix(10)))
    }

    @Test func aZeroWidthStripHoldsNothing() {
        var history = WaveformHistory()
        columns(5, level: 1, into: &history)
        columns(1, level: 1, width: 0, into: &history)
        #expect(history.samples.isEmpty)
    }
}

@Suite struct WaveformHistoryDetectorTests {
    @Test func theFlagDecidesWhatIsStored() {
        var history = WaveformHistory()
        columns(4, level: 1, into: &history)
        #expect(close(history.reference, 1))
        columns(1, level: 0.9, voiced: false, into: &history)
        #expect(history.samples.last == 0, "loud noise is a dot")
        #expect(close(history.reference, 0.991), "and lets the peak decay")
        columns(1, level: 0.01, voiced: true, into: &history)
        // So quiet against the peak that it sits on the gate: voiced, but drawn as a dot.
        #expect(history.samples.last == WaveformHistory.gate)
        columns(1, level: 0.9, into: &history)
        #expect(history.samples.last == 0, "once a detector spoke, no flag is silence")
        columns(1, level: 0.08, voiced: true, into: &history)
        #expect((history.samples.last ?? 0) >= WaveformHistory.gate, "the gate level itself, voiced, is kept")
    }
}

@Suite struct WaveformHistoryMarksTests {
    @Test func withoutScrollOnlyTheLiveColumnIsDrawn() {
        var history = WaveformHistory()
        columns(6, level: 1, into: &history)
        history.ingest(level: 1)
        let marks = history.marks(width: 100, scrolls: false)
        #expect(marks == [WaveformMark(x: 97.5, sample: history.sample(for: 1))])
    }

    // Reduce Motion never pushes a column, so whatever the live column holds
    // must come from the latest frame, not from everything since the strip appeared.
    @Test func withoutScrollTheLiveColumnGoesBackToADotWhenTheVoiceStops() {
        var history = WaveformHistory()
        history.ingest(level: WaveformHistory.level(meter: 0.6), voiced: true)
        for _ in 0 ..< 5 {
            history.ingest(level: WaveformHistory.level(meter: 0.12), voiced: false)
        }
        let marks = history.marks(width: 100, scrolls: false)
        #expect(marks.count == 1)
        #expect(marks.first?.sample == 0, "\(marks)")
    }

    @Test func withoutScrollAVoicedLatestFrameIsABar() {
        var history = WaveformHistory()
        history.ingest(level: WaveformHistory.level(meter: 0.12), voiced: false)
        history.ingest(level: WaveformHistory.level(meter: 0.6), voiced: true)
        let sample = history.marks(width: 100, scrolls: false).first?.sample ?? 0
        #expect(WaveformHistory.column(sample, gate: WaveformHistory.gate, height: 26) != .dot)
    }

    @Test func withoutScrollOrDetectorTheGateReadsTheLatestFrame() {
        var history = WaveformHistory()
        history.ingest(level: 1)
        history.ingest(level: 0.05)
        #expect(history.marks(width: 100, scrolls: false) == [WaveformMark(x: 97.5, sample: 0)])
    }

    @Test func scrollingTheLiveColumnStillShowsTheLoudestFrameOfTheColumn() {
        var history = WaveformHistory()
        history.ingest(level: 1, voiced: true)
        history.ingest(level: 0.05, voiced: false)
        #expect(history.marks(width: 100, scrolls: true).last?.sample == history.sample(for: 1))
    }

    @Test func scrollingDrawsTheHistoryThenTheLiveColumn() {
        var history = WaveformHistory()
        columns(3, level: 0, into: &history)
        let marks = history.marks(width: 100, scrolls: true)
        #expect(marks.map(\.x) == [87.5, 92.5, 97.5, 97.5])
    }

    @Test func columnsPastTheLeftEdgeAreNotDrawn() {
        var history = WaveformHistory()
        columns(20, level: 0, into: &history)
        let marks = history.marks(width: 20, scrolls: true)
        #expect(marks.allSatisfy { $0.x >= -WaveformHistory.barWidth })
        #expect(marks.map(\.x) == [-2.5, 2.5, 7.5, 12.5, 17.5, 17.5])
    }
}
