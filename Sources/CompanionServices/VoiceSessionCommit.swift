import CompanionCore
import Foundation

/// End of a user turn: read what the ear heard (or take the server's own
/// segment), route it to a focused field or to the agent, and sense the
/// context around it. Split out of VoiceSession when it crossed the
/// 400-line gate. What they touch is not `private` any more but still
/// actor-isolated: the actor, not the access level, is what keeps this
/// state single-threaded.
extension VoiceSession {
    /// End of a user turn. A segmenting ear (9j-1) hands the turn's final
    /// text directly; otherwise it is read from the ear's running transcript.
    func commitTurnFromNative() async {
        let closesHold = commitClosesHold
        commitClosesHold = false
        // The server segmented the turn: its text is final, commit at once.
        if let segment = earSegment {
            earSegment = nil
            audit.consume()
            commitTimeline()
            await realtime.commitWithText(segment, context: await senseVoice())
            return
        }
        // Let the last native partial settle before reading it. A cancel here
        // means the session is tearing down — drop the turn, don't commit.
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
        } catch {
            screen?.cancel()
            return
        }
        // v1 is hybrid-only: Apple is the ear. Without it (Speech denied) there
        // is no input path — say so once, don't spin responding to nothing.
        guard audit.isLive else {
            Log.app("voice: no native ear (Speech Recognition not authorized) "
                + "— enable it in System Settings › Privacy › Speech Recognition")
            if closesHold { eventBox.yield(.heardNothing) }
            screen?.cancel()
            return
        }
        let text = audit.turnText()
        var target: FocusedField?
        var notice: DictationNotice?
        switch await destination() {
        case .dictation(let field): target = field
        case .agent(let why): notice = why
        }
        // Dictated words are the user's document, not ours: they never
        // reach the log (corpus spec 11).
        if target == nil { audit.logTurn() }
        // Mark everything recognized so far as this turn's — the recognizer
        // keeps running (a restart re-enters its ~12 s cold start).
        audit.consume()
        guard !text.isEmpty else {
            if closesHold { eventBox.yield(.heardNothing) }
            screen?.cancel()
            return
        }
        if target != nil { screen?.cancel() }
        if let target, await dictate(text, into: target) { return }
        commitTimeline()
        await realtime.commitWithText(text, context: await senseVoice())
        if notice == .needsAccessibility {
            eventBox.yield(.dictationFailed(.needsAccessibility))
        }
    }

    /// True when the words landed in the field. On any failure they go to
    /// Companion instead: nothing the user said is lost, and never pasted
    /// anywhere but the field probed at press.
    func dictate(_ text: String, into field: FocusedField) async -> Bool {
        guard let injector else { return false }
        switch await injector.inject(text, into: field) {
        case .injected(let count, let route):
            commitTimeline()
            Log.app("dictation: pasted \(count) chars into \(field.app) via \(route.rawValue)")
            // The words ride the event for the island's result card only;
            // the log above stays at the count (dictation-never-logged).
            eventBox.yield(.dictated(app: field.app, text: DictatedText(text)))
            return true
        case .failed(let reason):
            Log.app("dictation: \(reason) in \(field.app); the words go to Companion")
            if reason == .needsAccessibility {
                eventBox.yield(.dictationFailed(.needsAccessibility))
            }
            return false
        }
    }

    /// Sensed per spoken turn, within the budget; the source is voice.
    private func senseVoice() async -> TurnContext? {
        guard let sensor else { return nil }
        let config = configProvider.current
        var ctx = await sensor.sense(config.contextChannels, budget: config.contextBudget)
        ctx.source = .voice
        if config.contextChannels.contains(.screen), let screen {
            let brief = await screen.finish(wait: .seconds(2))
            ctx.screenSummary = brief.summary
            ctx.screenSnippets = brief.snippets
            ctx.screenPending = brief.pending
            ctx.pointed = brief.pointed
        }
        return ctx
    }
}
