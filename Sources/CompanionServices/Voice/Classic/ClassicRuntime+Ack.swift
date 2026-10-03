import CompanionCore
import Foundation

/// What the racers in `actAcknowledging` report.
private enum ToolRace: Sendable {
    case done(ClassicRuntime.ActedRound)
    case slow
    /// A sheet of the round is about to show.
    case parked
    /// The round ended first: there is no rest to undo.
    case quiet
}

/// What a round left for the turn loop.
struct ActedTurns: Sendable {
    let turns: [Turn]
    /// The voice's "no" refused one of the round's sheets: the turn ends
    /// there, without another model round (its line said unless cut).
    let refusedByVoice: Bool
}

/// Wave 16h-2 (criterion 1): the turn's own line before work the user would
/// otherwise wait on in silence. It lives in the runtime, not the reducer:
/// the reducers decide chrome and capture, the runtime decides words — the
/// same split the router's own replies (`respond`) already follow.
extension ClassicRuntime {
    static let defaultSlowToolWait: @Sendable () async -> Void = {
        do {
            try await Task.sleep(for: Acknowledgement.slowToolAfter)
        } catch {
            // Cancelled: the tool finished first; the caller checks.
        }
    }

    /// Says `line` when nothing speakable was said yet this turn, and
    /// threads it with the reply. Stateless filtering on purpose: an element
    /// the model left open in the stateful filter must not swallow our own
    /// line. It touches only the mouth and the ports, never the runtime's
    /// turn state, because `actAcknowledging` calls it while `act` runs.
    func acknowledge(
        _ line: String, _ mouth: inout TurnMouth, apply: @Sendable (TurnEvent) async -> Void
    ) async {
        guard Acknowledgement.isNeeded(saidSoFar: mouth.said) else { return }
        await sayOwn(line, &mouth, apply: apply, marking: .acknowledged)
    }

    /// One fixed line of ours into the turn's voice and thread.
    func sayOwn(
        _ line: String, _ mouth: inout TurnMouth, apply: @Sendable (TurnEvent) async -> Void,
        marking point: TurnTimeline.Point? = nil
    ) async {
        let clean = SpeechFilter.clean(line)
        guard !clean.isEmpty else { return }
        if !mouth.started {
            mouth.started = true
            await apply(.firstSentence)
        }
        if let point { await markTimeline?(point) }
        // A press over the line (code review M1): the synthesizer was already
        // stopped for the next hold, and a line queued now would sound in it.
        if Task.isCancelled { return }
        Log.app("voice: own line chars=\(clean.count) ack=\(point == .acknowledged)")
        await synthesizer.enqueue(clean)
        mouth.spoken += (mouth.spoken.isEmpty ? "" : " ") + clean
    }

    /// `act`, raced against `slowToolWait`: a round still running when the
    /// wait ends is acknowledged while it keeps running. A round whose sheet
    /// shows rests the turn, so the question can be asked in the gap, and
    /// takes the voice back when it ends (classic-spoken-yes-parent-sheet).
    /// Structured, so a press that cuts the turn cancels every racer.
    func actAcknowledging(
        _ calls: [ToolCallRef], said text: String, heard: String,
        using parentTools: any ParentToolExecuting, language: AppLanguage,
        _ mouth: inout TurnMouth, apply: @escaping @Sendable (TurnEvent) async -> Void
    ) async -> ActedTurns {
        let line = Acknowledgement.isNeeded(saidSoFar: mouth.said)
            ? calls.first.map { Acknowledgement.working(tool: $0.name, language) } : nil
        let wait = slowToolWait
        let unverified = mouth.unverifiedTyped
        let (parks, parkSink) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        var rested = false
        let round = await withTaskGroup(of: ToolRace.self) { group -> ActedRound? in
            group.addTask {
                .done(await self.actRound(
                    calls, said: text, heard: heard, using: parentTools, language: language,
                    unverified: unverified, onParked: { _ in
                        parkSink.yield()
                        return true
                    }))
            }
            // One park per round is enough: the turn stays at rest until the
            // round ends, so its later sheets are asked in the same gap.
            group.addTask {
                for await _ in parks { return .parked }
                return .quiet
            }
            if line != nil {
                group.addTask {
                    await wait()
                    return .slow
                }
            }
            var round: ActedRound?
            for await result in group {
                switch result {
                case .done(let done):
                    round = done
                    parkSink.finish()
                    group.cancelAll()
                case .parked:
                    guard round == nil, !Task.isCancelled else { continue }
                    await apply(.sheetParked)
                    rested = await isTurnParked?() ?? false
                case .slow:
                    // At rest the gap is the question's: a line now would
                    // talk over it.
                    guard round == nil, !rested, !Task.isCancelled, let line else { continue }
                    await acknowledge(line, &mouth, apply: apply)
                case .quiet:
                    continue
                }
            }
            return round
        }
        // A cut turn's mark is already gone, and a new turn's park is not
        // this one's to end.
        if rested, !Task.isCancelled { await apply(.sheetResumed) }
        // Folded in here, after the racers ended: the round never writes the
        // turn's state while the acknowledgement reads it.
        guard let round else { return ActedTurns(turns: [], refusedByVoice: false) }
        Self.absorb(round, into: &mouth)
        // Karen's plan answer 3: after a spoken no the turn ends on the fixed
        // line alone; a click on Deny still hands the refusal to the model.
        // Only a sheet that really ended refused: a click to Allow that beat
        // the voice's no (the reducer dropped it) is the click's.
        let refused = takeRefusedByVoice(among: round.deniedSheets)
        // A mark whose sheet ended otherwise is spent with its round.
        for id in round.shownSheets { forgetRefusedByVoice(id) }
        if refused, !Task.isCancelled {
            await sayOwn(Escalation.approvalRefusedSpoken(language), &mouth, apply: apply)
        }
        return ActedTurns(turns: round.turns, refusedByVoice: refused)
    }
}
