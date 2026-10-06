import CompanionCore
import SwiftUI

// The bar and card states (16f, 16m-2): what it heard, what it is doing,
// the meter and the brake.
extension IslandView {
    @ViewBuilder
    func status(_ state: IslandState) -> some View {
        if state.line == .dropZones {
            IslandDropZones(zone: geometry.dropZone)
                .modifier(contentSlot(.card))
        } else if case .receipt(let receipt) = state.line {
            receiptCard(receipt)
                .modifier(contentSlot(.card))
        } else if case .followUp(let title) = state.line {
            IslandFollowUpRow(title: title, onDrop: { chat.followUp = nil })
                .modifier(contentSlot(.conversation))
        } else if case .dictationResult(let app, let text) = state.line {
            dictationCard(app: app, text: text)
                .modifier(contentSlot(.card))
        } else if let notice = IslandNotice.content(for: state.line) {
            IslandNoticeCard(content: notice,
                             pausesClock: NoticeHoverRule.viewPauses(state.line),
                             onHover: { chat.session.send(.noticeCardHover($0)) },
                             onAction: perform,
                             onDismiss: { dismissNotice(state.line) })
                .task(id: IslandNotice.expiringChatError(state.line)) {
                    if let text = IslandNotice.expiringChatError(state.line) {
                        await chat.expireIslandError(text)
                    }
                }
                // Enters and leaves on the card's own clocks, as the sheet does.
                .transition(.islandCard(reduceMotion: reduceMotion))
                .modifier(contentSlot(.card))
        } else {
            statusRows(state)
        }
    }

    func statusRows(_ state: IslandState) -> some View {
        VStack(alignment: .leading, spacing: IslandGrid.groupGap) {
            if Self.voiceStage(state) {
                IslandVoiceStage(voice: voice, text: latestReply.map(Self.replyText) ?? "",
                                 startedAt: replyStart, showsStop: IslandStop.inVoiceStage(state),
                                 visuals: latestReply.map(Self.inlineVisuals) ?? (nil, []),
                                 orbSpace: orbSpace, onStop: stop)
                    .environment(\.diagramRenderer, diagrams)
                    .environment(\.fileSaver, saveFile)
                    .modifier(contentSlot(.field))
            } else {
                statusRow(state)
            }
            VStack(alignment: .leading, spacing: IslandGrid.groupGap) {
                Group {
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
                    // While it speaks the voice stage carries the words.
                    if !Self.voiceStage(state),
                       state.meter == .agent || (state.light == .green && state.line == .completed) {
                        reply(state)
                    }
                }
                .islandContentColumn()
                if case .job = state.line, let job = chat.session.projection.job {
                    // Arc's run is always in view, its rail on the lead column;
                    // the pointer or the field opens it to every step.
                    IslandRunCard(job: job, expanded: runCardShows(state))
                        .transition(reduceMotion ? .opacity : .opacity.combined(
                            with: .offset(y: RunCardMetrics.riseOffset)))
                }
            }
            .modifier(contentSlot(.conversation))
            // The sheet animates by its own transition, never by an animation on the
            // stack: the success light keeps its own spring when both change together.
            VStack(spacing: Space.none) {
                if let request = state.approval {
                    ApprovalSheet(request: request, surface: .island) { approved, remember in
                        guard clickGate(for: request).accepts else { return }
                        chat.approvalAnswer(for: request)(approved, remember)
                    }
                    // The window grows before the content fades in: until it
                    // is visible the buttons take no clicks at all.
                    .allowsHitTesting(clickGate(for: request).takesClicks)
                    // A new request is a new sheet: without the id the
                    // reused view keeps the old ring and toggle (19-1b M1).
                    .id(request.requestId)
                    // The transition carries its own clocks, in and out, like Incredible's card.
                    .transition(.islandCard(reduceMotion: reduceMotion))
                }
            }
            .modifier(contentSlot(.card))
        }
    }

    /// Arc's grid: the mark in the lead column, the line in the content
    /// column, controls in the trail. Every state but speaking uses the same columns.
    func statusRow(_ state: IslandState) -> some View {
        IslandGridRow {
            leadMark(state)
        } content: {
            // Text states swap: "Escucho" leaves up, "Pienso" comes from
            // below. Keyed on the kind of line, so a job's next step
            // updates in place instead of swapping.
            ZStack(alignment: .leading) {
                if case .none = state.line {} else {
                    IslandStatusText(line: state.line)
                        .shimmering(active: IslandCopy.shimmers(state.line))
                        .id(IslandCopy.swapKey(state.line))
                        .transition(IslandMotionBudget.headerSwap.travels(reduceMotion: reduceMotion)
                            ? AnyTransition(IslandHeaderSwapTransition(swap: IslandMotionBudget.headerSwap))
                            : AnyTransition.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The lines travel 120 % of their height: outside the row they must not show.
            .clipped()
            .modifier(IslandVoiceOverLine(line: state.line))
            // Each property carries its own curve; this only keeps the leaving line alive
            // until the slowest of them is done.
            .animation(IslandMotionBudget.headerSwap.lifetime(reduceMotion: reduceMotion).animation,
                       value: IslandCopy.swapKey(state.line))
        } trail: {
            statusTrail(state)
        }
        .modifier(contentSlot(.field))
    }

    /// Speaking takes Arc's voice block; a job keeps its run in the lead
    /// column, and an offered action keeps the row whose trail holds it.
    static func voiceStage(_ state: IslandState) -> Bool {
        state.meter == .agent && !isJob(state.line) && state.action == nil
    }

    /// The lead column's mark: the run's loader during a job, the orb while
    /// it listens, thinks or speaks, and otherwise the status dot, the way
    /// Arc's agent run leads its status with one.
    @ViewBuilder
    func leadMark(_ state: IslandState) -> some View {
        if case .job = state.line, let job = chat.session.projection.job {
            IslandLoader(status: AgentRunModel.status(job.steps), size: AgentRunMetrics.loader)
                .foregroundStyle(ArcTone.foreground.color)
        } else if Self.leadHoldsMeter(state) {
            meter(state)
                .matchedGeometryEffect(id: IslandOrbTravel.id, in: orbSpace)
        } else {
            IslandLight(light: state.light)
        }
    }

    static func isJob(_ line: IslandState.Line) -> Bool {
        if case .job = line { return true }
        return false
    }

    static func leadHoldsMeter(_ state: IslandState) -> Bool {
        state.meter != .none || IslandCopy.shimmers(state.line)
    }

    @ViewBuilder
    func statusTrail(_ state: IslandState) -> some View {
        HStack(spacing: Space.x2) {
            if case .job = state.line, let job = chat.session.projection.job {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(RunCardModel.meta(jobStartedAt: job.startedAt, now: context.date))
                        .font(Fonts.geist(AgentRunMetrics.metaSize).monospacedDigit())
                        .foregroundStyle(ArcTone.textSecondary.color)
                        .contentTransition(.numericText())
                        // The tick rolls its digits; Reduce Motion just swaps them.
                        .animation(ArcMotion.press.animation(reduceMotion: reduceMotion), value: context.date)
                }
            }
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
            // "No permitir". Since the glow stopped marking the hands
            // (Karen, 2026-10-03, as in Incredible), the menu bar is where
            // a live session shows and stops.
            if Self.leadHoldsMeter(state) || Self.isJob(state.line) {
                IslandLight(light: state.light)
            }
        }
    }

    @ViewBuilder
    func meter(_ state: IslandState) -> some View {
        switch state.meter {
        case .none:
            // Arc's orb gives thinking a look of its own: it contracts into a slow swirl.
            if IslandCopy.shimmers(state.line) {
                IslandVoiceOrb(state: .thinking, size: IslandChrome.meterSide)
            }
        case .mic:
            // The orb's ripples carry the mic level; no separate waveform.
            IslandVoiceOrb(state: .listening, levels: voice.levels, size: IslandChrome.meterSide)
        case .agent:
            IslandVoiceOrb(state: .speaking, levels: voice.levels, size: IslandChrome.meterSide)
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

    /// Hover is read raw and judged against the size it is read at: it opens the run to every step.
    func runCardShows(_ state: IslandState) -> Bool {
        guard case .job = state.line else { return false }
        return RunCardModel.showsCard(rawHover: hoveringWork, size: state.size, focused: fieldFocused)
    }
}

/// The content root's hover target, present only at sizes that show content.
struct RunCardHoverRegion: ViewModifier {
    let enabled: Bool
    @Binding var hovering: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.contentShape(Rectangle()).onHover { hovering = $0 }
        } else {
            content
        }
    }
}

enum IslandOrbTravel {
    static let id = "island.orb"
}

extension IslandView {
    var clickGuardKey: ApprovalClickGuard.Key {
        ApprovalClickGuard.Key(requestId: state.approval?.requestId, contentVisible: contentVisible)
    }

    func armClickGuard() {
        clickGuard = ApprovalClickGuard.armed(
            clickGuard, requestId: state.approval?.requestId, contentVisible: contentVisible,
            now: Date().timeIntervalSince1970,
            reveal: IslandMotionBudget.revealTime(reduceMotion: reduceMotion))
    }

    func clickGate(for request: ApprovalRequest) -> ApprovalClickGuard.Gate {
        ApprovalClickGuard.gate(clickGuard, requestId: request.requestId, contentVisible: contentVisible,
                                now: Date().timeIntervalSince1970)
    }
}
