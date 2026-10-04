import CompanionCore
import SwiftUI

// P3: the voice line chip that carries a quiet turn under the island, as Incredible's.
extension IslandView {
    /// The chip's line, or nil: only in passive, and only for the reply that arrived
    /// during the quiet turn. It settles when the turn completes or rests.
    static func voiceLine(
        state: IslandState, projection: SessionProjection, latest: ChatMessage?, replyOfTurn: UUID?
    ) -> VoiceLine? {
        guard projection.presence == .passive, let latest, latest.id == replyOfTurn else { return nil }
        let settled = !state.quietTurn || projection.kind == .processing(.completed)
        let cards = islandResult(for: latest).map { [$0.title] } ?? []
        return VoiceLine.make(turn: latest.id, text: replyText(for: latest), spoken: 0,
                              settled: settled, cards: cards, quiet: true)
    }

    /// A new quiet turn forgets the last reply; one arriving while quiet, or in the same
    /// step the turn ends, is the turn's, and it stays so the chip can settle on it.
    static func replyOfTurn(kept: UUID?, wasQuiet: Bool, quiet: Bool, oldLatest: UUID?, latest: UUID?) -> UUID? {
        var reply = quiet && !wasQuiet ? nil : kept
        if quiet || wasQuiet, latest != oldLatest { reply = latest }
        return reply
    }

    /// The edge and the line are decided in one step: deciding the line from a reply
    /// the edge has not cleared yet flashed the last turn's answer (code review P3).
    static func followVoiceLine(
        kept: UUID?, old: VoiceLineFeed, new: VoiceLineFeed
    ) -> (reply: UUID?, line: VoiceLine?) {
        let reply = replyOfTurn(kept: kept, wasQuiet: old.quiet, quiet: new.quiet,
                                oldLatest: old.latest, latest: new.latest)
        guard let candidate = new.candidate, candidate.turn == reply else { return (reply, nil) }
        return (reply, candidate)
    }

    /// While the chip is up the island stays at least a pebble, so the panel holding
    /// the chip is not ordered out under it.
    static func holdingChip(_ state: IslandState, chipMounted: Bool) -> IslandState {
        guard chipMounted, state.size == .hidden else { return state }
        var held = state
        held.size = .pebble
        return held
    }

    /// The chip takes clicks only while lit, and never past the canvas.
    static func chipClickArea(_ frame: CGRect, visible: Bool) -> CGRect? {
        guard visible else { return nil }
        let area = frame.intersection(CGRect(
            x: 0, y: 0, width: IslandChrome.canvasWidth, height: IslandChrome.canvasHeight))
        return area.isNull ? nil : area
    }

    /// The candidate is the newest reply as if it were the turn's; `followVoiceLine`
    /// decides whether it is.
    var voiceLineFeed: VoiceLineFeed {
        VoiceLineFeed(
            quiet: state.quietTurn, latest: latestReply?.id,
            candidate: Self.voiceLine(state: state, projection: chat.session.projection,
                                      latest: latestReply, replyOfTurn: latestReply?.id))
    }

    /// The chip, and what keeps it in step with the session. Always present so the
    /// followers run whether or not a chip is mounted.
    var voiceLineLayer: some View {
        ZStack(alignment: .top) { voiceLineChip }
            .animation(reduceMotion ? nil : VoiceLineChipMotion.enter.animation, value: voiceLines.line?.turn)
            .onChange(of: voiceLineFeed, initial: true) { old, new in
                let step = Self.followVoiceLine(kept: replyOfTurn, old: old, new: new)
                replyOfTurn = step.reply
                voiceLines.show(step.line)
            }
            // The chip showing a reply is the reply shown; P2 left that report to it.
            .onChange(of: voiceLines.line?.turn) { _, turn in reportReplyShown(turn) }
    }

    @ViewBuilder
    private var voiceLineChip: some View {
        if let line = voiceLines.line {
            VoiceLineChip(
                line: line, visible: voiceLines.visible, startedAt: replyStart,
                speaking: chat.session.projection.kind == .processing(.speaking), levels: voice.levels,
                onEngage: engageVoiceLine)
                .offset(y: VoiceLineChipMetrics.top)
                .transition(VoiceLineChip.entering(reduceMotion: reduceMotion))
                // Visibility is part of the value, so lighting up again with the same
                // frame still reports it (code review P3).
                .onGeometryChange(for: CGRect?.self, of: { proxy in
                    Self.chipClickArea(proxy.frame(in: .named("islandCanvas")), visible: voiceLines.visible)
                }, action: { area in geometry.voiceLine = area })
                .onDisappear { geometry.voiceLine = nil }
        }
    }

    /// Clicking the chip is attending its reply, and the island takes the turn.
    private func engageVoiceLine() {
        resultAttention.attended()
        chat.session.send(.islandEngaged)
    }
}

/// What moves the chip: the quiet edge, the newest reply, and that reply as a line.
struct VoiceLineFeed: Equatable {
    let quiet: Bool
    let latest: UUID?
    let candidate: VoiceLine?
}
