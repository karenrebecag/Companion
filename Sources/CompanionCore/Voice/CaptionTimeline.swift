import Foundation

/// One word of the reply and when the voice said it.
package struct CaptionWord: Sendable, Equatable {
    package var text: String
    /// Wall-clock epoch seconds (`Date().timeIntervalSince1970`), the clock
    /// the island's TimelineView paints on; nil while the voice has not
    /// reached it. The panel ramps the word's light from this moment.
    package var saidAt: TimeInterval?

    package init(text: String, saidAt: TimeInterval? = nil) {
        self.text = text
        self.saidAt = saidAt
    }

    package var spoken: Bool { saidAt != nil }
}

/// What the captions paint. A settled caption is one the voice is done
/// with: every word is lit and nothing on it moves again.
package struct CaptionSnapshot: Sendable, Equatable {
    /// Bumped by every new reply or cut, so two captions with the same words
    /// still read as different ones.
    package var utterance: Int
    package var words: [CaptionWord]
    /// The player ran out of this reply's audio; the caption settles soon after.
    package var drained: Bool
    package var settled: Bool

    package init(
        utterance: Int = 0, words: [CaptionWord] = [], drained: Bool = false, settled: Bool = false
    ) {
        self.utterance = utterance
        self.words = words
        self.drained = drained
        self.settled = settled
    }

    package static let empty = CaptionSnapshot()

    /// Worth painting over the plain reply: there are words and the voice is
    /// still on them.
    package var isLive: Bool { !words.isEmpty && !settled }

    package var text: String { words.map(\.text).joined(separator: " ") }

    /// When each of `shown` was said. The panel shows the reply reshaped
    /// (markdown off, last 600 words). When that left the words as they are,
    /// or kept only their tail, they are read by position; only reshaped
    /// words walk the matcher's look-ahead.
    package func saidAt(for shown: [String]) -> [TimeInterval?] {
        let offset = words.count - shown.count
        if offset >= 0, words[offset...].map(\.text).elementsEqual(shown) {
            return words[offset...].map(\.saidAt)
        }
        var matcher = CaptionMatcher()
        var out = [TimeInterval?](repeating: nil, count: shown.count)
        for word in words {
            guard let at = word.saidAt else { break }
            let before = matcher.spoken
            matcher.cross(word.text, in: shown)
            for index in before..<matcher.spoken { out[index] = at }
        }
        return out
    }
}

/// The words of one spoken reply, lit as its audio is heard (gap 2, after
/// Incredible 0.2.36's caption source: a word is spoken once the played
/// audio crosses its start, and the caption settles 600 ms after the audio
/// drains). Incredible's TTS hands it each word's start; OpenAI's realtime
/// voice does not, so the starts are estimated here from the audio itself,
/// never from when the text arrived — the transcript runs ahead of the voice.
package struct CaptionTimeline: Sendable {
    package static let settleDelay: TimeInterval = 0.6
    /// A socket that dies without a close leaves no drain and no done behind;
    /// this long with no audio heard, the caption gives up waiting.
    package static let idleSettle: TimeInterval = 5
    /// Past this the caption stops growing: a runaway transcript must not
    /// cost a tokenizer pass and a paint per word forever.
    package static let maxWords = 2000
    /// A "word" longer than this is not speech; it is cut, not wrapped.
    package static let maxWordLength = 64
    /// The player's render clock trails what it was handed by up to a
    /// render quantum; a drain this close to the end is the end.
    package static let drainToleranceMs: Double = 100
    /// About 15 characters a second, a conversational voice at speed 1.0.
    /// Only the first reply leans on it: each finished reply measures the
    /// voice and pulls this toward what it heard.
    package static let defaultMsPerWeight: Double = 65

    private var msPerWeight: Double
    private var utterance = 0
    private var words: [String] = []
    /// The last word may continue in the next delta (no space after it yet).
    private var tailOpen = false
    private var textDone = false
    private var audioMs: Double = 0
    private var audioDone = false
    private var calibrated = false
    /// Where this reply's first audio sits in the player's position.
    private var anchorMs: Double?
    /// Words whose estimated start the played audio has passed.
    private var crossed = 0
    private var matcher = CaptionMatcher()
    /// Parallel to `words`: when each became spoken.
    private var saidAt: [TimeInterval?] = []
    private var drainedAt: TimeInterval?
    private var settled = false
    /// Recomputed only when words, audio or the rate change, not per tick.
    private var startsCache: [Double]?
    private var lastPlayedMs: Double?
    /// Restarted by every text or audio event and every move of the
    /// player; nil means the next tick starts it.
    private var progressAt: TimeInterval?
    /// Bumped whenever the snapshot would change, so a tick that changed
    /// nothing costs no rebuild of the words.
    package private(set) var revision = 0

    package init(msPerWeight: Double = Self.defaultMsPerWeight) {
        self.msPerWeight = msPerWeight
    }

    /// A new reply, or a cut: whatever was on screen goes. The measured rate
    /// stays — it is the voice's, not the reply's.
    package mutating func clear() {
        self = CaptionTimeline(msPerWeight: msPerWeight, utterance: utterance + 1, revision: revision + 1)
    }

    private init(msPerWeight: Double, utterance: Int, revision: Int) {
        self.msPerWeight = msPerWeight
        self.utterance = utterance
        self.revision = revision
    }

    package mutating func appendText(_ delta: String) {
        guard !settled, words.count < Self.maxWords else { return }
        progressAt = nil
        var tokens = Self.tokens(delta)
        if tailOpen, let first = delta.first, !first.isWhitespace, !tokens.isEmpty, let last = words.popLast() {
            tokens[0] = String((last + tokens[0]).prefix(Self.maxWordLength))
        }
        append(tokens)
        if let last = delta.last { tailOpen = !last.isWhitespace && !words.isEmpty }
        changed()
    }

    /// The server's final transcript replaces the deltas; a word already lit
    /// stays lit.
    package mutating func finishText(_ full: String) {
        guard !settled else { return }
        words = Array(Self.words(full).prefix(Self.maxWords))
        tailOpen = false
        progressAt = nil
        textDone = true
        changed()
        calibrateIfComplete()
    }

    /// `queuedAtMs`: the player's queued position before this chunk, which
    /// for the reply's first chunk is where its audio will start playing.
    package mutating func appendAudio(ms: Double, queuedAtMs: Double) {
        guard !settled, ms > 0 else { return }
        if anchorMs == nil { anchorMs = queuedAtMs }
        audioMs += ms
        if drainedAt != nil { revision += 1 }
        drainedAt = nil
        startsCache = nil
        progressAt = nil
    }

    /// The response is over: no more audio is coming for it.
    package mutating func finishAudio(at now: TimeInterval) {
        guard !settled else { return }
        audioDone = true
        startsCache = nil
        // Nothing will ever play, so nothing would ever drain: words left
        // dim forever read as a voice that is about to speak.
        if !words.isEmpty, audioMs == 0 {
            settle(at: now)
            return
        }
        // The player ran dry before the response said it was done: the
        // settle runs from now, when the reply is known to be over.
        if drainedAt != nil { drainedAt = now }
        calibrateIfComplete()
    }

    /// `playedMs`: the player's position at the drain. A drain that comes
    /// before this reply's own audio has played out belongs to an earlier
    /// reply, and is not this one's end.
    package mutating func drained(at now: TimeInterval, playedMs: Double) {
        guard !settled, !words.isEmpty, let anchorMs,
              playedMs >= anchorMs + audioMs - Self.drainToleranceMs
        else { return }
        if drainedAt == nil { revision += 1 }
        drainedAt = now
    }

    package mutating func advance(playedMs: Double, now: TimeInterval) {
        guard !settled else { return }
        // Only after the response is done: mid-reply, a drain is an underrun.
        if audioDone, let drainedAt, now - drainedAt >= Self.settleDelay {
            settle(at: now)
            return
        }
        // The player reached the end of a finished reply: that is the drain,
        // whether or not its signal arrives.
        if audioDone, drainedAt == nil, let anchorMs, playedMs >= anchorMs + audioMs {
            drainedAt = now
            revision += 1
        }
        if playedMs != lastPlayedMs || progressAt == nil {
            lastPlayedMs = playedMs
            progressAt = now
        } else if let progressAt, now - progressAt >= Self.idleSettle {
            settle(at: now)
            return
        }
        guard let anchorMs else { return }
        // At the anchor nothing of this reply has been heard yet.
        let elapsed = playedMs - anchorMs
        guard elapsed > 0 else { return }
        let starts = currentStarts()
        let before = matcher.spoken
        var lagMs = 0.0
        while crossed < words.count, starts[crossed] <= elapsed {
            matcher.cross(words[crossed], in: words)
            lagMs = elapsed - starts[crossed]
            crossed += 1
        }
        // The tick lands up to one interval after the voice crossed the
        // start; dating the word back by that lag keeps the light on the voice.
        let at = now - lagMs / 1000
        for index in before..<matcher.spoken where saidAt[index] == nil {
            saidAt[index] = at
            revision += 1
        }
    }

    /// Still worth ticking: a reply is on its way or on screen.
    package var isActive: Bool { !settled && (!words.isEmpty || anchorMs != nil) }

    package var snapshot: CaptionSnapshot {
        CaptionSnapshot(
            utterance: utterance,
            words: zip(words, saidAt).map { CaptionWord(text: $0, saidAt: $1) },
            drained: drainedAt != nil,
            settled: settled)
    }

    /// Whitespace-separated words, with closing punctuation spoken apart
    /// ("hola ,") joined back to the word it closes.
    package static func words(_ text: String) -> [String] {
        var out: [String] = []
        join(tokens(text), into: &out)
        return out
    }

    private static let closing: Set<Character> = [".", ",", ":", ";", "!", "?", "…", ")", "]", "}", "%", "»", "”", "’"]

    /// Split on whitespace, with control and format characters (bidi
    /// overrides, zero-width) dropped: they say nothing and could reorder
    /// what is painted.
    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).compactMap { token in
            let kept = String(String.UnicodeScalarView(token.unicodeScalars.filter {
                $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
            })).prefix(maxWordLength)
            return kept.isEmpty ? nil : String(kept)
        }
    }

    private static func join(_ tokens: [String], into words: inout [String]) {
        for token in tokens {
            guard words.count < maxWords || closing.contains(token.first ?? " ") else { return }
            if let first = token.first, closing.contains(first), let last = words.popLast() {
                words.append(last + token)
            } else {
                words.append(token)
            }
        }
    }

    private mutating func append(_ tokens: [String]) {
        Self.join(tokens, into: &words)
    }

    private mutating func changed() {
        matcher.clamp(to: words.count)
        crossed = min(crossed, words.count)
        saidAt = Array(saidAt.prefix(words.count))
            + [TimeInterval?](repeating: nil, count: max(words.count - saidAt.count, 0))
        startsCache = nil
        revision += 1
    }

    private mutating func settle(at now: TimeInterval) {
        settled = true
        matcher.finish(count: words.count)
        saidAt = saidAt.map { $0 ?? now }
        drainedAt = nil
        revision += 1
    }

    private mutating func currentStarts() -> [Double] {
        if let startsCache { return startsCache }
        let starts = estimatedStarts()
        startsCache = starts
        return starts
    }

    // HACK: a word's share of the reply's audio is its share of the
    // characters, so pauses at commas and periods smear over the words
    // around them. Upgrade trigger: a voice provider that returns per-word
    // timing (ElevenLabs' with-timestamps stream) — its starts replace
    // `estimatedStarts` and the matcher stays as it is.
    private func estimatedStarts() -> [Double] {
        var starts: [Double] = []
        starts.reserveCapacity(words.count)
        var weight = 0.0
        for word in words {
            starts.append(weight)
            weight += Self.weight(word)
        }
        guard weight > 0 else { return starts }
        let rate: Double
        if textDone, audioDone, audioMs > 0 {
            rate = audioMs / weight
        } else {
            // The text received so far is often ahead of its audio, so the
            // audio can only prove the voice slower than the prior, never
            // faster.
            rate = max(msPerWeight, audioMs / weight)
        }
        return starts.map { $0 * rate }
    }

    private mutating func calibrateIfComplete() {
        guard !calibrated, textDone, audioDone, audioMs > 0 else { return }
        let weight = words.reduce(0) { $0 + Self.weight($1) }
        guard weight > 0 else { return }
        calibrated = true
        // Halfway, so one odd reply (a lone "Sí.") cannot swing the next one.
        msPerWeight = (msPerWeight + audioMs / weight) / 2
        startsCache = nil
    }

    /// Characters plus the space after the word.
    private static func weight(_ word: String) -> Double {
        Double(word.count + 1)
    }
}

/// Marks words spoken as the voice reaches them. Each word the audio
/// crosses is looked for among the next few on screen, so a word the screen
/// spells differently, or a dash with nothing to say, is stepped over
/// instead of stalling the line.
package struct CaptionMatcher: Sendable, Equatable {
    package static let lookAhead = 4
    /// Misses in a row before the line steps one word forward anyway.
    package static let missTolerance = 2

    package private(set) var spoken = 0
    private var misses = 0

    package init() {}

    package mutating func cross(_ word: String, in words: [String]) {
        let target = Self.normalized(word)
        guard !target.isEmpty else { return }
        let end = min(words.count, spoken + Self.lookAhead)
        if spoken < end, let hit = (spoken..<end).first(where: { Self.normalized(words[$0]) == target }) {
            spoken = hit + 1
            misses = 0
            return
        }
        misses += 1
        if misses > Self.missTolerance, spoken < words.count {
            spoken += 1
            misses = 0
        }
    }

    package mutating func clamp(to count: Int) {
        spoken = min(spoken, count)
    }

    package mutating func finish(count: Int) {
        spoken = count
        misses = 0
    }

    private static func normalized(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
