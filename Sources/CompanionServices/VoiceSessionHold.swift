import CompanionCore
import Foundation

/// Wave 12b: the hold — press, release, discard, and where its words go.
/// Split out of `VoiceSession.swift` at the 800-line gate (Wave 15d-1),
/// the same pattern `VoiceSessionTimeline` uses: not `private`, but still
/// actor-isolated by the actor itself.
/// What a provisional press still owes once it is confirmed a hold.
struct OwedHoldWork: Sendable {
    let realtime: Bool
}

/// A provisional press that started nothing yet.
struct DeferredHold: Sendable {
    let dictate: Bool
    let pressedAt: TimeInterval
}

extension VoiceSession {
    /// FN on the way down (code review 2026-09-24): only local, reversible
    /// work starts — the mic and the on-device ear.
    public func holdProvisionally() async {
        await hold(provisional: true)
    }

    /// The tap threshold passed with the key still down: the press is a
    /// hold, so what it owes may leave the machine, and a reply in flight
    /// may be cut. Idempotent.
    public func confirmHold() async {
        if let deferred = deferredHold {
            deferredHold = nil
            await beginHold(dictate: deferred.dictate, provisional: false, pressedAt: deferred.pressedAt)
            return
        }
        guard let owed = owedHoldWork else { return }
        owedHoldWork = nil
        startConfirmedWork(realtime: owed.realtime)
    }

    public func hold(dictate: Bool = false, provisional: Bool = false) async {
        // A press that may still be a tap never cuts a reply, never takes a
        // release tail back and never opens a socket: it waits, whole.
        if provisional, !pressIsLocal {
            deferredHold = DeferredHold(dictate: dictate, pressedAt: now())
            return
        }
        await beginHold(dictate: dictate, provisional: provisional, pressedAt: now())
    }

    /// True when a press only starts the local mic and ear.
    private var pressIsLocal: Bool {
        guard !releaseTailing else { return false }
        let snap = machine.snapshot
        switch snap.state {
        case .idle, .error: return true
        case .listening: return snap.pipeline == .classic
        case .connecting, .thinking, .speaking: return false
        }
    }

    private func beginHold(dictate: Bool, provisional: Bool, pressedAt: TimeInterval) async {
        await cutAnnouncement()
        deferredHold = nil
        owedHoldWork = nil
        holdGeneration += 1
        // 15d-2: a press inside the release tail takes that hold back — the
        // tail never commits, and this hold keeps its clock, route and ears.
        let resumed = releaseTailing
        releaseTailing = false
        if resumed { timeline.released = nil }
        // A press that bounces while the session still connects is the same
        // hold: its clock keeps the first press (code review 2026-09-06).
        let bounced = resumed || (timeline.pressed != nil && timeline.released == nil)
        if !bounced {
            classic.parentTools?.beginTurn()
            flushTimeline()
            timeline = TurnTimeline()
            timeline.mark(.pressed, at: pressedAt)
        }
        // Every hold starts with the ear at zero: words the ear delivers
        // late for the previous hold are not this one's (security review
        // 2026-09-06). A resumed hold is the same hold: what it heard
        // before the tail is still its own.
        if !resumed {
            audit.consume()
            lastPartial = ""
        }
        let realtime = openAIKey() != nil
        if !bounced { rememberStack(openAI: realtime) }
        // A bounce is the same hold: it keeps the field it already decided
        // on, instead of paying for a second Accessibility round trip and
        // announcing twice (code review 2026-09-06).
        if !bounced {
            routeHold(realtime: realtime, dictate: dictate)
            if provisional {
                owedHoldWork = OwedHoldWork(realtime: realtime)
            } else {
                startConfirmedWork(realtime: realtime)
            }
        }
        // Hold is the text path (14b). Hands-free `start()` still opens realtime.
        await apply(.holdPressed(preferRealtime: false))
    }

    /// What leaves the machine for a hold: the screen for vision and the
    /// context fan-out.
    private func startConfirmedWork(realtime: Bool) {
        let seesScreen = configProvider.current.contextChannels.contains(.screen)
        // Pointing never leaves the machine, so every pipeline samples it.
        if seesScreen { screen?.beginPointing() }
        // Vision needs the OpenAI key; classic-only holds must not upload.
        if realtime, seesScreen {
            screen?.begin(app: nil)
        }
        fanOut()
    }

    /// Where this hold's words go: 15b-1, FN (`dictate == false`) is always
    /// the agent — the field is never even probed. Only the dictation key's
    /// own hold asks, on its own task so a hung app in front delays
    /// nothing. Classic (no key) always talks (code review 2026-09-06).
    func routeHold(realtime: Bool, dictate: Bool) {
        dictationTask?.cancel()
        dictationTask = nil
        guard dictate, realtime, let fieldProbe else { return }
        let box = eventBox
        dictationTask = Task.detached(priority: .userInitiated) {
            let trusted = fieldProbe.isTrusted()
            let field = trusted ? fieldProbe.focusedField() : nil
            let destination = DictationRouter.destination(
                mode: .dictation, field: field, trusted: trusted)
            switch destination {
            case .dictation(let target):
                box.yield(.dictating(app: target.app))
            case .agent(let notice):
                if let notice { Log.app("dictation: \(notice); the hold talks to Companion") }
            }
            return destination
        }
    }

    /// The destination this hold decided on, waited for only here.
    func destination() async -> DictationDestination {
        guard let dictationTask else { return .agent(nil) }
        self.dictationTask = nil
        return await dictationTask.value
    }

    /// Wave 12c: what boot can do for the first hold without opening the
    /// mic, the socket or any prompt. Measured, in the log. The Keychain is
    /// not touched: a read can be a dialog (a build whose signature the
    /// item's ACL does not list), and a dialog at launch is not a warm-up.
    public func prewarm() async {
        let t0 = now()
        await mic.prewarm()
        let t1 = now()
        _ = await reachability.isOnline
        let t2 = now()
        Log.app("prewarm: mic \(Self.ms(t0, t1)) · net \(Self.ms(t1, t2))")
    }

    static func ms(_ from: TimeInterval, _ to: TimeInterval) -> String {
        "\(Int(((to - from) * 1000).rounded())) ms"
    }

    /// Release = ForceEndpoint: what the native ear heard goes now, without
    /// asking the server's VAD whether the sentence was over.
    public func release() async {
        // Past the threshold by definition, even if `.confirmed` lost the
        // race to the key-up.
        await confirmHold()
        // Asking the mic suspends the actor; a press that lands in that gap
        // owns the hold and this release is stale (code review 2026-09-06).
        let generation = holdGeneration
        let hasSpeech = await mic.receivedBuffer
        guard generation == holdGeneration else { return }
        timeline.mark(.released, at: now())
        guard await rideReleaseTail(generation) else { return }
        await completeHold(hasSpeech: hasSpeech)
    }

    /// 15d-2: the mic keeps feeding the on-device ear for
    /// `releaseTail` after the key comes up — the last syllable is still in
    /// flight then (Incredible: 300 ms). False when a press took the hold
    /// back meanwhile: that hold commits on its own release, once.
    private func rideReleaseTail(_ generation: Int) async -> Bool {
        guard releaseTail > 0 else { return true }
        releaseTailing = true
        do {
            try await Task.sleep(for: .seconds(releaseTail))
        } catch {
            // Cut short, the words still go: losing them is worse.
            Log.app("voice: release tail cut short")
        }
        guard generation == holdGeneration else { return false }
        releaseTailing = false
        return true
    }

    public func discard() async {
        // A tap that never became a hold started nothing to undo; the reply
        // or the release tail it landed on goes on untouched.
        if deferredHold != nil {
            deferredHold = nil
            return
        }
        owedHoldWork = nil
        // Esc inside the release tail: the commit it was riding toward is
        // what this discard cancels.
        if releaseTailing {
            releaseTailing = false
            holdGeneration += 1
        }
        dictationTask?.cancel()
        dictationTask = nil
        classic.cancelPressedContext()
        screen?.cancel()
        // A tap never calls release(), so it never marked `.released`; without
        // this the next hold's bounce check reads the abandoned hold as still
        // in flight and keeps its stale press mark (live 2026-09-22).
        flushTimeline()
        await apply(.holdDiscarded)
    }
}
