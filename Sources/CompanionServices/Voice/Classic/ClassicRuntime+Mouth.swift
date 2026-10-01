import CompanionCore
import Foundation

/// Wave 15d-5: one serial stream carries the model's deltas and the first-cut
/// stall tick, so the round loop stays the only place that touches the
/// mouth's buffer or enqueues speech — no lock, and no way for the tick's
/// utterance to reach the synthesizer out of order with a sentence.
enum MouthEvent: Sendable {
    case delta(ChatDelta)
    case stall
}

/// At most one stall timer per stream; cancelled when the stream ends.
private final class StallTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var armed = false
    private var cancelled = false

    func arm(_ body: @escaping @Sendable () async -> Void) {
        lock.withLock {
            guard !armed, !cancelled else { return }
            armed = true
            task = Task { await body() }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            task?.cancel()
        }
    }
}

extension ClassicRuntime {
    /// 400 ms after the first token, what is buffered is spoken even without
    /// a clause mark (spec 15d §2): Incredible starts audio 1-3 ms after it.
    static let firstCutStall: Duration = .milliseconds(400)

    static let defaultFirstCutWait: @Sendable () async -> Void = {
        do {
            try await Task.sleep(for: firstCutStall)
        } catch {
            // Cancelled: the stream already ended; the caller checks.
        }
    }

    func mouthEvents(
        _ source: AsyncThrowingStream<ChatDelta, Error>
    ) -> (events: AsyncThrowingStream<MouthEvent, Error>, arm: @Sendable () -> Void) {
        let (events, continuation) = AsyncThrowingStream<MouthEvent, Error>.makeStream()
        let forward = Task {
            do {
                for try await delta in source { continuation.yield(.delta(delta)) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let timer = StallTimer()
        let wait = firstCutWait
        continuation.onTermination = { _ in
            forward.cancel()
            timer.cancel()
        }
        let arm: @Sendable () -> Void = {
            timer.arm {
                await wait()
                guard !Task.isCancelled else { return }
                continuation.yield(.stall)
            }
        }
        return (events, arm)
    }
}

/// A goal object found in the reply text, with its size for the log.
struct ContentHandoff: Sendable {
    let handoff: Handoff
    let chars: Int
}

/// Wave 15f: one turn's mouth — the cut buffer, the JSON guard and the
/// language gate — threaded through the rounds as a single value.
struct TurnMouth {
    var buffer = MouthBuffer()
    var json = HandoffInText()
    var gate: MouthLanguageGate
    /// 16h-1: the single filter on the way to the voice, and the length rule
    /// for a turn whose detail is on a card.
    var filter = SpeechFilter()
    var budget = SpeechBudget()
    var started = false
    /// The filter took something out of this turn.
    var filtered = false
    /// Everything the model wrote that was speakable (JSON already out).
    var spoken = ""
    /// 16h-1: a tool put a card on screen this turn, so what is still said
    /// is a line pointing at it (`SpeechBudget`), not the card read aloud.
    var cardThisTurn = false
    /// 16h-1: texts `type_text` injected that no `read_focused` has confirmed
    /// yet; a later read in the same turn turns them into a success line.
    var unverifiedTyped: [ClassicRuntime.TypedAttempt] = []
    /// 16h-1: the status line of every call this turn that changed something.
    /// If the filter swallowed what the model said about them, the app says
    /// them itself (`sayMissingEffects`).
    var effectLines: [String] = []
    /// 16h-2 (security M1): our own lines this turn owes the user, said
    /// after the reply (a spoken yes the sheet did not take).
    var owedLines: [String] = []

    init(language: AppLanguage, recognizer: any LanguageRecognizing, heard: String) {
        gate = MouthLanguageGate(language: language, recognizer: recognizer, heard: heard)
    }

    /// The reply minus what the mouth dropped (foreign reasoning, leaks): the
    /// thread and the transcript must not keep those. The length budget trims
    /// only the voice; the thread keeps the full text, which is the point of
    /// a card carrying the detail.
    var said: String { SpeechFilter.clean(saidPart(of: spoken)) }

    /// Code review 2026-09-25 (LOW-2): a round's text as the voice said it,
    /// for the model's next round.
    func saidPart(of text: String) -> String {
        MouthLanguageGate.removing(gate.dropped, from: text)
    }
}

extension ClassicRuntime {
    /// Every cut reaches the synthesizer through here, past the language
    /// gate. The log counts what was dropped, never what it said.
    func say(_ cut: String, _ mouth: inout TurnMouth) async {
        let before = mouth.gate.dropped.count
        let kept = mouth.gate.admit(cut)
        for dropped in mouth.gate.dropped[before...] {
            Log.app("mouth: dropped reason=language chars=\(dropped.count)")
        }
        guard let kept else { return }
        let clean = mouth.filter.admit(kept)
        let removed = Self.visibleCount(kept) - Self.visibleCount(clean)
        if removed > 0 {
            mouth.filtered = true
            Log.app("mouth: dropped reason=leak chars=\(removed)")
        }
        await speak(clean, &mouth)
    }

    /// Past the length rule, to the synthesizer.
    private func speak(_ clean: String, _ mouth: inout TurnMouth) async {
        if mouth.cardThisTurn { mouth.budget.cardShown = true }
        guard !clean.isEmpty, let said = mouth.budget.admit(clean) else { return }
        await synthesizer.enqueue(said)
    }

    /// End of the turn: what an element left open was holding back was text
    /// after all, so it is said now.
    func flushHeld(_ mouth: inout TurnMouth) async {
        await speak(mouth.filter.flush(), &mouth)
    }

    /// The safety net (16h-1 S-C): when the filter or the language gate took
    /// something out of this turn, an effect the model reported may have gone
    /// with it. The app then says the tool's own status line, which is what
    /// the thread already shows, so a change is never done in silence.
    func sayMissingEffects(_ mouth: inout TurnMouth, apply: @Sendable (TurnEvent) async -> Void) async {
        guard mouth.filtered || !mouth.gate.dropped.isEmpty else { return }
        let said = mouth.said
        for line in mouth.effectLines where !said.contains(line) {
            if !mouth.started {
                mouth.started = true
                await apply(.firstSentence)
            }
            await synthesizer.enqueue(line)
            mouth.spoken += (mouth.spoken.isEmpty ? "" : " ") + line
        }
    }

    /// Blanks come and go at the edges of a cut without anything leaking.
    private static func visibleCount(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    /// 15f-1: a goal object in the content is found here; what happens to
    /// it is `propose`'s call, not a delegation (security review 2026-09-25).
    func guardJSON(_ step: HandoffInText.Step) -> (speakable: String, handoff: ContentHandoff?) {
        if step.droppedChars > 0 {
            Log.app("mouth: dropped reason=json chars=\(step.droppedChars)")
        }
        guard let found = step.handoff else { return (step.speakable, nil) }
        guard onDelegate != nil else {
            Log.app("mouth: dropped reason=json chars=\(step.handoffChars)")
            return (step.speakable, nil)
        }
        return (step.speakable, ContentHandoff(handoff: found, chars: step.handoffChars))
    }

    /// Security review 2026-09-25 (HIGH-1): a goal the model WROTE carries
    /// none of a `delegate` call's trust. An echo of what the turn perceived
    /// (clipboard, screen, tool results) is dropped; anything else is asked
    /// in our own words and runs only once the approval seam — the sheet or
    /// a spoken "yes" through `resolve_approval` — answers yes. No seam
    /// means nobody can answer: fail closed. False when a press cut the
    /// turn while the question was being enqueued.
    func propose(
        _ found: ContentHandoff, perceived: [String],
        round text: inout String, _ mouth: inout TurnMouth,
        language: AppLanguage, apply: @Sendable (TurnEvent) async -> Void
    ) async -> Bool {
        if HandoffProposal.isEcho(goal: found.handoff.goal, in: perceived) {
            Log.app("mouth: dropped reason=json-echo chars=\(found.chars)")
            return true
        }
        guard let onDelegate, let approvals = parentGuard.approvals else {
            Log.app("mouth: dropped reason=json-unapproved chars=\(found.chars)")
            return true
        }
        Log.app("mouth: proposal source=content chars=\(found.chars)")
        let request = HandoffProposal.request(
            for: found.handoff, id: "handoff-\(UUID().uuidString)")
        parentGuard.onRequest?(request)
        let handoff = found.handoff
        // Unstructured on purpose: the answer comes in a later turn (or the
        // sheet), long after this one has finished; `Approvals` auto-denies
        // at its deadline, so the wait is bounded.
        Task {
            if await approvals.request(request).approved {
                Log.app("mouth: proposal approved")
                onDelegate(handoff)
            } else {
                Log.app("mouth: proposal declined")
            }
        }
        let separator = mouth.spoken.isEmpty || mouth.spoken.hasSuffix(" ") ? "" : " "
        return await take(
            separator + HandoffProposal.question(language), round: &text, &mouth, apply: apply)
    }

    /// Speakable text into the stream and the buffer; false when a press
    /// cut the turn while its sentences were being enqueued.
    func take(
        _ piece: String, round text: inout String, _ mouth: inout TurnMouth,
        apply: @Sendable (TurnEvent) async -> Void
    ) async -> Bool {
        guard !piece.isEmpty else { return true }
        let piece = SpeechFilter.joiner(after: mouth.spoken, before: piece) + piece
        let voiced = SpeechFilter.stoppingLines(piece, after: mouth.spoken)
        if !mouth.started {
            mouth.started = true
            await apply(.firstSentence)
        }
        text += piece
        mouth.spoken += piece
        // Only a card that will paint shortens the voice: a fence that fails
        // to parse shows as code, and the answer stays whole.
        if !mouth.budget.cardShown, SpeechBudget.hasCard(in: mouth.spoken) {
            mouth.budget.cardShown = true
        }
        for sentence in mouth.buffer.append(voiced) {
            if Task.isCancelled { return false }
            await say(sentence, &mouth)
        }
        // After the gate: the bubble never shows a sentence the voice dropped.
        await thread.showStream(mouth.said)
        return true
    }
}
