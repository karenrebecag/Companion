import Foundation

/// Where the chrome rests, what the release tail is and how the voice's
/// snapshots land: the resting-kind helpers of the session reducer. Split from SessionMachine.swift when it
/// crossed the 400-line gate; like SessionMachineJobs it is the reducer, so
/// the gate that keeps a single writer of the projection lists it.
extension SessionMachine {
    /// A session a hold opened, resting with the mic closed and nothing of
    /// ours on screen that says the hardware is still taken. Hands-free
    /// muted from the window is not this: its button shows the state.
    var restingWarm: Bool {
        guard voice.state == .listening, voice.muted, voice.holdArmed, !projection.holding
        else { return false }
        switch projection.kind {
        case .idle, .hover, .processing(.completed): return true
        default: return false
        }
    }

    /// Released, and the voice has not moved past listening yet.
    var inReleaseTail: Bool {
        projection.kind == .processing(.pending) && voice.state == .listening
            && voice.holdArmed && !voice.muted
    }

    /// A press cancelled under the threshold never cut the reply, so the
    /// chrome goes back to it instead of painting Idle over a voice that
    /// is still talking.
    mutating func replyOrRestingKind() -> SessionKind {
        guard !jobInFront else { return .processing(.subAgentRunning) }
        switch voice.state {
        case .thinking: return .processing(.thinking)
        case .speaking: return .processing(.speaking)
        default: return restingKind()
        }
    }

    /// Where a hold that produced nothing lands: the job's row if one runs,
    /// otherwise Idle straight away (no Completed for nothing).
    mutating func restingKind() -> SessionKind {
        turnOver()
        return projection.job != nil ? .processing(.subAgentRunning) : .idle
    }

    /// Where the chrome goes when a piece of work ends: the job's row if one
    /// runs, the typed turn if one is open, the voice if it is live, and
    /// otherwise Completed with its timer.
    mutating func rest() -> [SessionEffect] {
        if jobInFront {
            projection.kind = .processing(.subAgentRunning)
            return []
        }
        if typedBusy {
            projection.kind = .processing(.thinking)
            return []
        }
        switch voice.state {
        case .listening where !voice.muted:
            projection.kind = .listening
        case .thinking:
            projection.kind = .processing(.thinking)
        case .speaking:
            projection.kind = .processing(.speaking)
        case .idle, .connecting, .error, .listening:
            // Her turn is over: a job still running takes the row back.
            guard projection.job == nil else {
                turnOver()
                projection.kind = .processing(.subAgentRunning)
                return []
            }
            projection.kind = .processing(.completed)
            return completedExpiry()
        }
        return []
    }

    /// A snapshot of the voice, landed on the chrome.
    mutating func observe(_ snapshot: TurnSnapshot) -> [SessionEffect] {
        voice = snapshot
        projection.pipeline = snapshot.pipeline
        projection.voice = Self.status(of: snapshot)
        switch snapshot.state {
        case .connecting:
            break
        case .listening where snapshot.muted:
            // The voice is warm with the mic closed: the chrome rests, except
            // while Pending waits for the text just sent, or while a press
            // is still being served.
            if projection.kind == .processing(.pending) || projection.holding { break }
            turnOver()
            if case .processing = projection.kind {
                return rest()
            }
            if projection.kind == .listening { projection.kind = .idle }
        case .listening:
            openTurn()
            // Every door into a turn starts the reel fresh (review 16m H1):
            // typed, hold, provisional hold, and this — the voice runtime.
            projection.touched = []
            projection.kind = .listening
        case .thinking:
            projection.kind = jobInFront ? .processing(.subAgentRunning) : .processing(.thinking)
        case .speaking:
            projection.kind = .processing(.speaking)
        case .idle:
            // Classic hold arms Speech while TurnMachine is still idle.
            // Clearing holding here dropped FN-up (live 2026-09-07).
            if projection.holding { break }
            projection.holding = false
            turnOver()
            if projection.job != nil {
                projection.kind = .processing(.subAgentRunning)
            } else if !typedBusy, projection.kind != .processing(.completed) {
                projection.kind = .idle
            }
        case .error:
            // The failure is a reason and a card, not a mode: the voice may
            // sit in its own error state, the chrome goes back to rest.
            let failure = snapshot.failure ?? .sessionDropped
            projection.holding = false
            turnOver()
            projection.interruption = .failure(failure)
            projection.notice = Self.card(for: failure)
            projection.cards = [Self.card(for: failure)]
            projection.kind = projection.job != nil
                ? .processing(.subAgentRunning) : .idle
            if Self.fades(Self.card(for: failure)) {
                return [.scheduleNoticeExpiry(Self.noticeDelay)]
            }
        }
        return []
    }
}

// P1: Incredible's presence. Here with rest because passive is the longest rest: the
// user has not touched the companion for a while.
extension SessionMachine {
    /// Incredible's `passive_after_secs` default (referencia local).
    package static let defaultPassiveAfter: TimeInterval = 600
    package static let maxPassiveAfter: TimeInterval = 86_400

    mutating func presence(after event: SessionEvent) -> [SessionEffect] {
        switch event {
        case .passiveAfterChanged(let seconds):
            passiveAfter = Self.boundedPassiveAfter(seconds)
            return rearmPassive()
        case .passiveExpired(let armedFor):
            // Every change and interaction moves the arm, so only the latest wait counts.
            guard armedFor == passiveArm else { return [] }
            // A turn in progress keeps its island: the wait starts over instead.
            switch projection.kind {
            case .idle, .hover:
                projection.presence = .passive
                return []
            case .listening, .processing:
                return rearmPassive()
            }
        default:
            return Self.isInteraction(event) ? rearmPassive() : []
        }
    }

    /// Any interaction is active again and starts the wait over. A new arm makes
    /// the one still running stale, and with 0 nothing is armed at all.
    private mutating func rearmPassive() -> [SessionEffect] {
        projection.presence = .active
        passiveArm += 1
        guard passiveAfter > 0 else { return [] }
        return [.schedulePassive(passiveAfter, armedFor: passiveArm)]
    }

    /// Nothing negative or undefined arms a wait (it is never), and nothing longer than
    /// a day reaches the clock, whose conversion of a huge interval is not safe.
    static func boundedPassiveAfter(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return min(seconds, maxPassiveAfter)
    }

    /// What the user does, never what the companion does on its own: a reply, a job
    /// step or the hands acting must not keep it awake. The user's words in the ear
    /// count, so talking without the key keeps it active.
    static func isInteraction(_ event: SessionEvent) -> Bool {
        switch event {
        case .pressed, .pressedProvisionally, .tapped, .hoverEntered, .typedSubmitted,
             .released, .holdConfirmed, .holdCancelled, .partialTranscript,
             .approvalAnswered, .approvalSpoken, .undoPressed, .noticeDismissed,
             .dictationCardHover, .dictationCardCopied, .dictationHidden,
             .stop, .stopVoice, .stopJob:
            true
        default:
            false
        }
    }
}
