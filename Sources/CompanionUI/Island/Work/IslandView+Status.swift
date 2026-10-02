import CompanionCore
import SwiftUI

// The bar and card states (16f, 16m-2): what it heard, what it is doing,
// the meter and the brake.
extension IslandView {
    @ViewBuilder
    func status(_ state: IslandState) -> some View {
        if state.line == .dropZones {
            IslandDropZones(zone: geometry.dropZone)
        } else if case .receipt(let receipt) = state.line {
            receiptCard(receipt)
        } else if case .followUp(let title) = state.line {
            IslandFollowUpRow(title: title, onDrop: { chat.followUp = nil })
        } else if case .dictationResult(let app, let text) = state.line {
            dictationCard(app: app, text: text)
        } else if let notice = IslandNotice.content(for: state.line) {
            IslandNoticeCard(content: notice, onAction: perform,
                             onDismiss: { dismissNotice(state.line) })
                .task(id: IslandNotice.expiringChatError(state.line)) {
                    if let text = IslandNotice.expiringChatError(state.line) {
                        await chat.expireIslandError(text)
                    }
                }
        } else {
            statusRows(state)
        }
    }

    func statusRows(_ state: IslandState) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(spacing: Space.x3) {
                meter(state)
                // Text states swap: "Escucho" leaves up, "Pienso" comes from
                // below. Keyed on the kind of line, so a job's next step
                // updates in place instead of swapping.
                ZStack(alignment: .leading) {
                    if case .none = state.line {} else {
                        IslandStatusText(line: state.line)
                            .shimmering(active: IslandCopy.shimmers(state.line))
                            .id(IslandCopy.swapKey(state.line))
                            .transition(.islandSwap(IslandMotionBudget.textSwap.resolved(reduceMotion: reduceMotion)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(IslandMotionBudget.textSwap.animation(reduceMotion: reduceMotion),
                           value: IslandCopy.swapKey(state.line))
                if let action = state.action {
                    Button(IslandCopy.action(action)) { perform(action) }
                        .buttonStyle(CapsuleChipStyle(ink: .island, density: .compact))
                }
                if IslandStop.asChip(state) {
                    Button(Localized.string("island.stop")) { stop() }
                        .buttonStyle(CapsuleChipStyle(ink: .island, density: .compact))
                }
                // 19-1c: the "Manos"/"Detener manos" chip left the island
                // (Karen, feedback en vivo): during the sheet it duplicated
                // "No permitir", and at rest the screen aura is the hands
                // signal. Stopping a live session lives in the menu bar.
                IslandLight(light: state.light)
            }
            if let partial = state.partial, !partial.isEmpty {
                // 16m-2: quieter while the ear can still change it, full
                // ink once the release fixes it.
                IslandTranscript(text: partial, fixed: state.meter != .mic)
            }
            if let receipt = state.receipt, state.approval == nil {
                IslandReceiptRow(receipt: receipt) { chat.session.send(.undoPressed(id: receipt.id)) }
            }
            if let item = IslandReel.item(chat.session.projection.touched), state.approval == nil {
                IslandReel(item: item)
            }
            if case .job = state.line, let job = chat.session.projection.job {
                // Waving the checklist away falls back to the small
                // runcard, never to silence (review 16m).
                if job.steps.count > WorkStateMetrics.checklistAt,
                   dismissedChecklist != job.startedAt
                {
                    IslandChecklist(job: job, onDismiss: { dismissedChecklist = job.startedAt })
                } else {
                    IslandRunCard(job: job)
                }
                let agents = WorkStateMetrics.agents(job.steps)
                if !agents.isEmpty {
                    IslandAgentBars(agents: agents)
                }
            }
            if state.meter == .agent || (state.light == .green && state.line == .completed) {
                reply(state)
            }
            // Each animation scoped to what it moves: the success light keeps
            // its own spring when the line and the light change together.
            VStack(spacing: Space.none) {
                if let request = state.approval {
                    ApprovalSheet(request: request) { approved, remember in
                        guard ApprovalClickGuard.accepts(clickGuard, at: Date().timeIntervalSince1970)
                        else { return }
                        chat.answerApproval(approved, remember: remember)
                    }
                    // A new request is a new sheet: without the id the
                    // reused view keeps the old ring and toggle (19-1b M1).
                    .id(request.requestId)
                    .transition(.islandReveal(IslandMotionBudget.approval.resolved(reduceMotion: reduceMotion)))
                }
            }
            .animation(IslandMotionBudget.approval.animation(reduceMotion: reduceMotion),
                       value: state.approval?.requestId)
        }
    }

    @ViewBuilder
    func meter(_ state: IslandState) -> some View {
        switch state.meter {
        case .none:
            EmptyView()
        case .mic:
            Orb(state: .listening, levels: voice.levels, accentColor: Semantic.accent)
                .frame(width: IslandChrome.meterSide, height: IslandChrome.meterSide)
            IslandWaveBars(level: voice.levels.mic)
        case .agent:
            // Icon swap: while it speaks the orb is the brake.
            ZStack {
                if IslandStop.asOrb(state) {
                    IslandStopOrb(action: stop).transition(iconSwap)
                } else {
                    Orb(state: .speaking, levels: voice.levels, accentColor: Semantic.accent)
                        .frame(width: IslandChrome.meterSide, height: IslandChrome.meterSide)
                        .transition(iconSwap)
                }
            }
            .animation(.expoOut(IslandMotionBudget.iconSwap.duration), value: IslandStop.asOrb(state))
            IslandWaveBars(level: voice.levels.agent)
        }
    }

    /// Stop is that job's brake when the job card is showing; otherwise it is
    /// the voice's, and the jobs keep going. Either way the island says so,
    /// briefly, as Incredible's pill does.
    func stop() {
        IslandStop.stop(chat)
        cancelledTask?.cancel()
        cancelled = true
        cancelledTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(IslandStop.cancelledFor)) } catch { return }
            cancelled = false
        }
    }
}
