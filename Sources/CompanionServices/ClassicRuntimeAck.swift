import CompanionCore
import Foundation

/// Which of the two racers in `actAcknowledging` answered first.
private enum ToolRace: Sendable {
    case done(ClassicRuntime.ActedRound)
    case slow
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
    /// wait ends is acknowledged while it keeps running. Structured, so a
    /// press that cuts the turn cancels both racers.
    func actAcknowledging(
        _ calls: [ToolCallRef], said text: String, heard: String,
        using parentTools: any ParentToolExecuting, language: AppLanguage,
        _ mouth: inout TurnMouth, apply: @escaping @Sendable (TurnEvent) async -> Void
    ) async -> [Turn] {
        guard Acknowledgement.isNeeded(saidSoFar: mouth.said), let first = calls.first else {
            return await act(calls, said: text, heard: heard, using: parentTools, language: language)
        }
        let wait = slowToolWait
        let line = Acknowledgement.working(tool: first.name, language)
        let unverified = unverifiedTyped
        let round = await withTaskGroup(of: ToolRace.self) { group -> ActedRound? in
            group.addTask {
                .done(await self.actRound(
                    calls, said: text, heard: heard, using: parentTools, language: language,
                    unverified: unverified))
            }
            group.addTask {
                await wait()
                return .slow
            }
            var round: ActedRound?
            for await result in group {
                switch result {
                case .done(let done):
                    round = done
                    group.cancelAll()
                case .slow:
                    guard round == nil, !Task.isCancelled else { continue }
                    await acknowledge(line, &mouth, apply: apply)
                }
            }
            return round
        }
        // Folded in here, after both racers ended: the round never writes the
        // turn's state while the acknowledgement reads it.
        guard let round else { return [] }
        absorb(round)
        return round.turns
    }
}
