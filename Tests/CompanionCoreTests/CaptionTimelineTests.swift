import CompanionCore
import Testing

/// Which words a caption paints lit, in order.
private func lit(_ timeline: CaptionTimeline) -> [Bool] {
    timeline.snapshot.words.map(\.spoken)
}

/// A whole reply already in: its text and its audio, both finished.
private func finishedReply(
    _ text: String, audioMs: Double, queuedAtMs: Double = 0, msPerWeight: Double = 50
) -> CaptionTimeline {
    var timeline = CaptionTimeline(msPerWeight: msPerWeight)
    timeline.clear()
    timeline.appendText(text)
    timeline.appendAudio(ms: audioMs, queuedAtMs: queuedAtMs)
    timeline.finishText(text)
    timeline.finishAudio(at: 0)
    return timeline
}

@Suite struct CaptionTimelineTests {
    @Test func closingPunctuationJoinsTheWordBeforeIt() {
        #expect(CaptionTimeline.words("Hola , mundo. ¿Qué tal ?") == ["Hola,", "mundo.", "¿Qué", "tal?"])
        #expect(CaptionTimeline.words("  \n ").isEmpty)
    }

    /// "one two three four" weighs 4+4+6+5 = 19; 1900 ms of audio is 100 ms
    /// a unit, so the words start at 0, 400, 800 and 1400 ms.
    @Test func aWordLightsWhenThePlayedAudioReachesItsShareOfTheReply() {
        var timeline = finishedReply("one two three four", audioMs: 1900)
        timeline.advance(playedMs: 399, now: 0)
        #expect(lit(timeline) == [true, false, false, false])
        timeline.advance(playedMs: 400, now: 0)
        #expect(lit(timeline) == [true, true, false, false])
        timeline.advance(playedMs: 1399, now: 0)
        #expect(lit(timeline) == [true, true, true, false])
        timeline.advance(playedMs: 1400, now: 0)
        #expect(lit(timeline) == [true, true, true, true])
        #expect(timeline.snapshot.isLive)
    }

    @Test func textThatArrivedAheadOfItsAudioStaysDim() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two three four")
        timeline.advance(playedMs: 5000, now: 0)
        #expect(lit(timeline) == [false, false, false, false])
    }

    @Test func aReplyQueuedBehindEarlierAudioStartsWhereItsOwnAudioDoes() {
        var timeline = finishedReply("one two three four", audioMs: 1900, queuedAtMs: 3000)
        timeline.advance(playedMs: 2999, now: 0)
        #expect(lit(timeline) == [false, false, false, false])
        timeline.advance(playedMs: 3400, now: 0)
        #expect(lit(timeline) == [true, true, false, false])
    }

    /// While the reply streams, the rate is the prior (50) until the audio
    /// already received proves the voice slower; the words then spread out.
    @Test func theEstimateStretchesAsMoreAudioArrives() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two three four")
        timeline.appendAudio(ms: 400, queuedAtMs: 0)
        timeline.advance(playedMs: 250, now: 0)
        #expect(lit(timeline) == [true, true, false, false])
        timeline.appendAudio(ms: 1500, queuedAtMs: 400)
        timeline.advance(playedMs: 799, now: 0)
        #expect(lit(timeline) == [true, true, false, false])
        timeline.advance(playedMs: 800, now: 0)
        #expect(lit(timeline) == [true, true, true, false])
    }

    @Test func theFinalTextNeverUnlightsAWord() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two three")
        timeline.appendAudio(ms: 1000, queuedAtMs: 0)
        timeline.advance(playedMs: 300, now: 0)
        let before = lit(timeline).filter { $0 }.count
        timeline.finishText("one two three four")
        #expect(lit(timeline).filter { $0 }.count == before)
        #expect(timeline.snapshot.words.count == 4)
    }

    /// "Sí — claro": the dash has nothing to say and is never matched on
    /// its own; the next word, found within the look-ahead, lights it too.
    @Test func aWordWithNothingToSayIsCarriedByTheNextOne() {
        var timeline = finishedReply("Sí — claro", audioMs: 1100)
        timeline.advance(playedMs: 300, now: 0)
        #expect(lit(timeline) == [true, false, false])
        timeline.advance(playedMs: 500, now: 0)
        #expect(lit(timeline) == [true, true, true])
    }

    @Test func drainedAudioSettlesTheCaptionSixHundredMillisecondsLater() {
        var timeline = finishedReply("one two three four", audioMs: 1900)
        timeline.advance(playedMs: 500, now: 0)
        timeline.drained(at: 0, playedMs: 1900)
        timeline.advance(playedMs: 500, now: 0.59)
        #expect(!timeline.snapshot.settled)
        timeline.advance(playedMs: 500, now: 0.6)
        #expect(timeline.snapshot.settled)
        #expect(lit(timeline) == [true, true, true, true])
        #expect(!timeline.snapshot.isLive)
    }

    @Test func audioArrivingAfterADrainKeepsTheCaptionOpen() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two three four")
        timeline.appendAudio(ms: 200, queuedAtMs: 0)
        timeline.drained(at: 10, playedMs: 200)
        timeline.appendAudio(ms: 200, queuedAtMs: 200)
        timeline.advance(playedMs: 0, now: 11)
        #expect(!timeline.snapshot.settled)
    }

    @Test func aReplyThatNeverSoundedSettlesWhenTheResponseEnds() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two")
        timeline.finishText("one two")
        timeline.finishAudio(at: 0)
        #expect(timeline.snapshot.settled)
        #expect(lit(timeline) == [true, true])
    }

    @Test func clearingDropsTheWordsAndTheNextReplyAnchorsAgain() {
        var timeline = finishedReply("one two three four", audioMs: 1900)
        timeline.advance(playedMs: 1500, now: 0)
        let first = timeline.snapshot.utterance
        timeline.clear()
        #expect(timeline.snapshot.words.isEmpty)
        #expect(!timeline.snapshot.isLive)
        #expect(timeline.snapshot.utterance != first)
        timeline.appendText("five six")
        timeline.appendAudio(ms: 900, queuedAtMs: 5000)
        timeline.advance(playedMs: 4999, now: 0)
        #expect(lit(timeline) == [false, false])
    }

    /// A finished reply measures the voice: 1900 ms over 19 units is 100,
    /// and the next reply starts from halfway between the prior and that.
    @Test func aFinishedReplyCalibratesTheNextEstimate() {
        var timeline = finishedReply("one two three four", audioMs: 1900, msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two three four")
        timeline.appendAudio(ms: 100, queuedAtMs: 0)
        timeline.advance(playedMs: 299, now: 0)
        #expect(lit(timeline) == [true, false, false, false])
        timeline.advance(playedMs: 300, now: 0)
        #expect(lit(timeline) == [true, true, false, false])
    }
}

@Suite struct CaptionSaidAtTests {
    /// The tick that notices a crossing comes late; the word is dated back to
    /// when the voice reached it. "one" starts at 0 and "two" at 400 ms.
    @Test func aWordIsDatedToWhenTheVoiceReachedIt() {
        var timeline = finishedReply("one two three four", audioMs: 1900)
        timeline.advance(playedMs: 430, now: 10)
        let said = timeline.snapshot.words.map(\.saidAt)
        #expect(said[0] == 10 - 0.03)
        #expect(said[1] == 10 - 0.03)
        #expect(said[2] == nil)
        timeline.advance(playedMs: 900, now: 10.5)
        #expect(timeline.snapshot.words[0].saidAt == 10 - 0.03)
        #expect(timeline.snapshot.words[2].saidAt == 10.5 - 0.1)
    }

    @Test func settlingDatesTheRemainingWordsToTheSettle() {
        var timeline = finishedReply("one two", audioMs: 800)
        timeline.advance(playedMs: 100, now: 0.1)
        timeline.drained(at: 1, playedMs: 800)
        #expect(timeline.snapshot.drained)
        timeline.advance(playedMs: 800, now: 1.6)
        #expect(timeline.snapshot.words.map(\.saidAt) == [0, 1.6])
    }

    @Test func theShownWordsTakeTheirTimesThroughTheMatcher() {
        let caption = CaptionSnapshot(words: [
            CaptionWord(text: "Hola,", saidAt: 1),
            CaptionWord(text: "**mundo**", saidAt: 2),
            CaptionWord(text: "otra", saidAt: nil),
        ])
        #expect(caption.saidAt(for: ["Hola,", "mundo", "otra"]) == [1, 2, nil])
    }

    /// The panel can drop a word the caption has (a dash it filters out):
    /// the look-ahead skips it instead of stalling every word after it.
    @Test func aWordMissingFromThePanelDoesNotStallTheRest() {
        let caption = CaptionSnapshot(words: [
            CaptionWord(text: "Sí", saidAt: 1),
            CaptionWord(text: "—", saidAt: 1.2),
            CaptionWord(text: "claro", saidAt: 1.4),
        ])
        #expect(caption.saidAt(for: ["Sí", "claro"]) == [1, 1.4])
    }
}

@Suite struct CaptionMatcherTests {
    private let words = ["a", "b", "c", "d", "e", "f", "g"]

    @Test func aWordWithinTheLookAheadIsFound() {
        var matcher = CaptionMatcher()
        matcher.cross("D", in: words)
        #expect(matcher.spoken == 4)
    }

    @Test func aWordPastTheLookAheadIsAMiss() {
        var matcher = CaptionMatcher()
        matcher.cross("e", in: words)
        #expect(matcher.spoken == 0)
    }

    @Test func threeMissesInARowStepOneWordForward() {
        var matcher = CaptionMatcher()
        matcher.cross("x", in: words)
        matcher.cross("x", in: words)
        #expect(matcher.spoken == 0)
        matcher.cross("x", in: words)
        #expect(matcher.spoken == 1)
    }

    @Test func punctuationAndCaseDoNotBreakAMatch() {
        var matcher = CaptionMatcher()
        matcher.cross("¿QUÉ?", in: ["qué", "tal"])
        #expect(matcher.spoken == 1)
    }
}

/// Review fixes (gap 2): what a stream can do to a caption that a tidy reply
/// never does.
@Suite struct CaptionTimelineEdgeTests {
    /// An underrun mid-reply drains the player; the reply is not over.
    @Test func aDrainBeforeTheResponseEndsNeverSettles() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two three four")
        timeline.appendAudio(ms: 200, queuedAtMs: 0)
        timeline.drained(at: 10, playedMs: 200)
        timeline.advance(playedMs: 200, now: 11)
        #expect(!timeline.snapshot.settled)
        timeline.appendAudio(ms: 200, queuedAtMs: 200)
        timeline.advance(playedMs: 300, now: 11.1)
        #expect(!timeline.snapshot.settled)
    }

    /// The player drained before `response.done` landed: the settle runs
    /// from the response's end.
    @Test func theResponseEndPicksUpADrainThatAlreadyHappened() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two")
        timeline.appendAudio(ms: 800, queuedAtMs: 0)
        timeline.finishText("one two")
        timeline.drained(at: 1, playedMs: 800)
        timeline.finishAudio(at: 2)
        timeline.advance(playedMs: 800, now: 2.59)
        #expect(!timeline.snapshot.settled)
        timeline.advance(playedMs: 800, now: 2.6)
        #expect(timeline.snapshot.settled)
    }

    /// Reply 1's drain lands after reply 2 began and queued its audio behind
    /// it: the player is not done with reply 2.
    @Test func aStaleDrainDoesNotSettleTheNextReply() {
        var timeline = finishedReply("one two", audioMs: 800)
        timeline.clear()
        timeline.appendText("three four")
        timeline.appendAudio(ms: 1000, queuedAtMs: 800)
        timeline.finishText("three four")
        timeline.finishAudio(at: 5)
        timeline.drained(at: 5, playedMs: 800)
        timeline.advance(playedMs: 900, now: 6)
        #expect(!timeline.snapshot.settled)
    }

    /// A socket that dies without a close leaves no drain behind: five
    /// seconds with no audio heard settles the caption instead.
    @Test func fiveSecondsWithoutAudioProgressSettles() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two")
        timeline.appendAudio(ms: 800, queuedAtMs: 0)
        timeline.advance(playedMs: 100, now: 0)
        timeline.advance(playedMs: 100, now: 4.9)
        #expect(!timeline.snapshot.settled)
        timeline.advance(playedMs: 100, now: CaptionTimeline.idleSettle)
        #expect(timeline.snapshot.settled)
    }

    @Test func audioStillPlayingIsProgress() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two")
        timeline.appendAudio(ms: 8000, queuedAtMs: 0)
        timeline.advance(playedMs: 100, now: 0)
        timeline.advance(playedMs: 4000, now: 4)
        timeline.advance(playedMs: 7900, now: 8)
        #expect(!timeline.snapshot.settled)
    }

    @Test func theCaptionStopsGrowingAtItsCap() {
        var timeline = CaptionTimeline()
        timeline.clear()
        let many = Array(repeating: "palabra", count: CaptionTimeline.maxWords + 50).joined(separator: " ")
        timeline.appendText(many)
        timeline.appendText(" otra")
        #expect(timeline.snapshot.words.count == CaptionTimeline.maxWords)
        timeline.finishText(many + " otra")
        #expect(timeline.snapshot.words.count == CaptionTimeline.maxWords)
    }

    /// Bidi overrides and zero-width characters say nothing and could
    /// reorder what is painted.
    @Test func controlAndFormatCharactersAreStripped() {
        #expect(CaptionTimeline.words("ho\u{200B}la \u{202E}mundo\u{202C} \u{200B}") == ["hola", "mundo"])
        var timeline = CaptionTimeline()
        timeline.clear()
        timeline.appendText("ho\u{200B}la \u{202E}mun")
        timeline.appendText("do")
        #expect(timeline.snapshot.words.map(\.text) == ["hola", "mundo"])
    }

    /// Deltas split words anywhere; the words come out the same as the
    /// whole text tokenized at once.
    @Test func deltasThatSplitWordsTokenizeLikeTheWholeText() {
        let text = "Hola , mun do. ¿Qué tal ?"
        var timeline = CaptionTimeline()
        timeline.clear()
        for chunk in ["Ho", "la ", ", mu", "n", " do", ". ¿Qu", "é tal", " ?"] { timeline.appendText(chunk) }
        #expect(timeline.snapshot.words.map(\.text) == CaptionTimeline.words(text))
    }

    @Test func aLeadingClosingTokenStandsAlone() {
        #expect(CaptionTimeline.words("., hola") == [".,", "hola"])
    }

    @Test func aLoneEllipsisIsAWordThatLightsOnSettle() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("…")
        timeline.appendAudio(ms: 300, queuedAtMs: 0)
        timeline.finishText("…")
        timeline.finishAudio(at: 0)
        timeline.advance(playedMs: 300, now: 0)
        #expect(timeline.snapshot.words.map(\.text) == ["…"])
        timeline.drained(at: 0, playedMs: 300)
        timeline.advance(playedMs: 300, now: 0.6)
        #expect(lit(timeline) == [true])
    }

    /// Audio can reach the client before any transcript: the words anchor
    /// where that first chunk was queued.
    @Test func wordsArrivingAfterTheirAudioAnchorAtTheFirstChunk() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendAudio(ms: 100, queuedAtMs: 500)
        timeline.appendText("one two")
        timeline.advance(playedMs: 500, now: 0)
        #expect(lit(timeline) == [false, false])
        timeline.advance(playedMs: 501, now: 0)
        #expect(lit(timeline) == [true, false])
    }

    /// "one two" weighs 4 + 4: at the first reply's 65 ms a unit, "two"
    /// starts at 260 ms.
    @Test func theFirstReplyLeansOnSixtyFiveMillisecondsAUnit() {
        var timeline = CaptionTimeline()
        timeline.clear()
        timeline.appendText("one two")
        timeline.appendAudio(ms: 50, queuedAtMs: 0)
        timeline.advance(playedMs: 259, now: 0)
        #expect(lit(timeline) == [true, false])
        timeline.advance(playedMs: 260, now: 0)
        #expect(lit(timeline) == [true, true])
    }

    @Test func nothingIsLitBeforeAnyAudioIsHeard() {
        var timeline = finishedReply("one two", audioMs: 800)
        timeline.advance(playedMs: 0, now: 0)
        #expect(lit(timeline) == [false, false])
    }
}

/// The rate each finished reply leaves for the next: halfway each time.
@Suite struct CaptionCalibrationTests {
    private func twoLightsAt(_ ms: Double, _ timeline: inout CaptionTimeline) -> Bool {
        timeline.clear()
        timeline.appendText("one two three four")
        timeline.appendAudio(ms: 10, queuedAtMs: 0)
        timeline.advance(playedMs: ms - 0.5, now: 0)
        let dimBefore = !lit(timeline)[1]
        timeline.advance(playedMs: ms, now: 0)
        return dimBefore && lit(timeline)[1]
    }

    private func reply(_ timeline: inout CaptionTimeline, audioMs: Double = 1900) {
        timeline.clear()
        timeline.appendText("one two three four")
        timeline.appendAudio(ms: audioMs, queuedAtMs: 0)
        timeline.finishText("one two three four")
        timeline.finishAudio(at: 0)
    }

    /// 50 -> 75 -> 87.5 -> 93.75 against a voice at 100 ms a unit.
    @Test func calibrationCompoundsOverReplies() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        for _ in 0..<3 { reply(&timeline) }
        #expect(twoLightsAt(4 * 93.75, &timeline))
    }

    @Test func finishingTwiceCalibratesOnce() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        reply(&timeline)
        timeline.finishText("one two three four")
        timeline.finishAudio(at: 0)
        timeline.clear()
        #expect(twoLightsAt(4 * 75, &timeline))
    }

    @Test func aCutReplyDoesNotCalibrate() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two three four")
        timeline.appendAudio(ms: 1900, queuedAtMs: 0)
        timeline.finishText("one two three four")
        timeline.clear()
        timeline.finishAudio(at: 0)
        #expect(twoLightsAt(4 * 50, &timeline))
    }

    @Test func aReplyWithNoAudioDoesNotCalibrate() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two three four")
        timeline.finishText("one two three four")
        timeline.finishAudio(at: 0)
        #expect(twoLightsAt(4 * 50, &timeline))
    }

    @Test func clearingKeepsTheRate() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        reply(&timeline)
        timeline.clear()
        timeline.clear()
        #expect(twoLightsAt(4 * 75, &timeline))
    }
}

@Suite struct CaptionMatcherEdgeTests {
    private let words = ["a", "b", "c", "d", "e", "f", "g"]

    @Test func aHitResetsTheMissCount() {
        var matcher = CaptionMatcher()
        matcher.cross("x", in: words)
        matcher.cross("x", in: words)
        matcher.cross("a", in: words)
        matcher.cross("x", in: words)
        matcher.cross("x", in: words)
        #expect(matcher.spoken == 1)
        matcher.cross("x", in: words)
        #expect(matcher.spoken == 2)
    }

    @Test func theForcedStepStopsAtTheLastWord() {
        var matcher = CaptionMatcher()
        matcher.cross("a", in: ["a"])
        for _ in 0..<6 { matcher.cross("x", in: ["a"]) }
        #expect(matcher.spoken == 1)
    }

    /// Had the dash counted as a miss, the step would have come with it.
    @Test func aWordWithNothingToSayIsNotAMiss() {
        var matcher = CaptionMatcher()
        matcher.cross("x", in: words)
        matcher.cross("x", in: words)
        matcher.cross("—", in: words)
        #expect(matcher.spoken == 0)
        matcher.cross("x", in: words)
        #expect(matcher.spoken == 1)
    }

    /// Only letters and digits count, so "3.5" and "35" are the same word.
    @Test func aDecimalMatchesWithOrWithoutItsPoint() {
        var exact = CaptionMatcher()
        exact.cross("3.5", in: ["3.5"])
        #expect(exact.spoken == 1)
        var bare = CaptionMatcher()
        bare.cross("3.5", in: ["35"])
        #expect(bare.spoken == 1)
    }

    @Test func theLookAheadReachesItsFirstAndLastSlotMidLine() {
        var first = CaptionMatcher()
        first.cross("a", in: words)
        first.cross("b", in: words)
        #expect(first.spoken == 2)
        var last = CaptionMatcher()
        last.cross("a", in: words)
        last.cross("e", in: words)
        #expect(last.spoken == 5)
        last.cross("x", in: words)
        var beyond = CaptionMatcher()
        beyond.cross("a", in: words)
        beyond.cross("f", in: words)
        #expect(beyond.spoken == 1)
    }
}

@Suite struct CaptionShownWordsTests {
    private func said(_ texts: [String], from start: Double = 0) -> CaptionSnapshot {
        CaptionSnapshot(words: texts.enumerated().map { CaptionWord(text: $1, saidAt: start + Double($0)) })
    }

    /// The panel keeps the last 600 words of a long reply: they are the
    /// caption's tail, read by position, not walked from the top.
    @Test func aCappedPanelReadsTheCaptionsTail() {
        let words = (0..<700).map { "w\($0)" }
        let shown = Array(words.suffix(600))
        let times = said(words).saidAt(for: shown)
        #expect(times.count == 600)
        #expect(times.first == 100)
        #expect(times.last == 699)
    }

    @Test func identicalWordsReadByPosition() {
        let caption = CaptionSnapshot(words: [CaptionWord(text: "a", saidAt: 1), CaptionWord(text: "a")])
        #expect(caption.saidAt(for: ["a", "a"]) == [1, nil])
    }
}

/// Review batch: the last rough edges of the drain, idle and size rules.
@Suite struct CaptionTimelineFinalTests {
    /// The render clock trails the queued total by up to a quantum.
    @Test func aDrainWithinOneHundredMillisecondsOfTheEndCounts() {
        var near = finishedReply("one two three four", audioMs: 1900)
        near.drained(at: 0, playedMs: 1800)
        near.advance(playedMs: 1800, now: 0.6)
        #expect(near.snapshot.settled)
        var early = finishedReply("one two three four", audioMs: 1900)
        early.drained(at: 0, playedMs: 1799)
        early.advance(playedMs: 1799, now: 0.6)
        #expect(!early.snapshot.settled)
    }

    /// A drain signal that never arrives: reaching the end is the drain.
    @Test func reachingTheEndOfADoneReplyArmsTheSettle() {
        var timeline = finishedReply("one two", audioMs: 800)
        timeline.advance(playedMs: 800, now: 1)
        #expect(timeline.snapshot.drained)
        timeline.advance(playedMs: 800, now: 1.6)
        #expect(timeline.snapshot.settled)
    }

    /// The first audio can land more than five seconds after the text.
    @Test func eventsKeepTheIdleClockFromRunningOut() {
        var timeline = CaptionTimeline(msPerWeight: 50)
        timeline.clear()
        timeline.appendText("one two")
        timeline.advance(playedMs: 0, now: 0)
        timeline.advance(playedMs: 0, now: 4)
        timeline.appendText(" three")
        timeline.advance(playedMs: 0, now: 8)
        timeline.appendAudio(ms: 800, queuedAtMs: 0)
        timeline.advance(playedMs: 0, now: 12)
        #expect(!timeline.snapshot.settled)
        timeline.advance(playedMs: 0, now: 17)
        #expect(timeline.snapshot.settled)
    }

    @Test func aWordIsCappedAtSixtyFourCharacters() {
        let long = String(repeating: "a", count: 100)
        #expect(CaptionTimeline.words(long).map(\.count) == [CaptionTimeline.maxWordLength])
        var timeline = CaptionTimeline()
        timeline.clear()
        timeline.appendText(String(repeating: "b", count: 40))
        timeline.appendText(String(repeating: "b", count: 40))
        #expect(timeline.snapshot.words.map(\.text.count) == [CaptionTimeline.maxWordLength])
    }

    @Test func aFullCaptionDoesNotReopenItsLastWord() {
        var timeline = CaptionTimeline()
        timeline.clear()
        timeline.appendText(Array(repeating: "w", count: CaptionTimeline.maxWords).joined(separator: " "))
        timeline.appendText("xyz")
        #expect(timeline.snapshot.words.last?.text == "w")
    }

    @Test func aTickThatChangesNothingLeavesTheRevision() {
        var timeline = finishedReply("one two", audioMs: 800)
        timeline.advance(playedMs: 100, now: 0)
        let revision = timeline.revision
        timeline.advance(playedMs: 200, now: 0.1)
        #expect(timeline.revision == revision)
        timeline.advance(playedMs: 450, now: 0.2)
        #expect(timeline.revision != revision)
    }
}
