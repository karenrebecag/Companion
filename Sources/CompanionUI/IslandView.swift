import CompanionCore
import SwiftUI

/// The island (Wave 12b), Incredible's notch bar since 16e: the app lives
/// here — ask, see what it heard, see the results. Paints `IslandState`;
/// never decides the kind.
public struct IslandView: View {
    var chat: ChatViewModel
    var voice: VoiceViewModel
    var hold: HoldSettingsModel
    var geometry: IslandGeometry
    let onShowMain: () -> Void
    let onSize: (IslandState.Size, CGFloat) -> Void
    /// Hands the keyboard back to the app in front once the field is done.
    let onReleaseKey: () -> Void
    /// The clip's captures (16i-2); absent, the two capture rows say so.
    let grabber: (any RegionGrabbing)?
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointer = HoldKeyClassifier()
    @State private var clickGuard: ApprovalClickGuard?
    @State private var draft = ""
    @State private var confirmingClear = false
    @FocusState private var fieldFocused: Bool
    /// The shape as drawn right now; `IslandMotion` walks it to the target.
    @State private var shown = CGSize.zero
    @State private var stage = IslandMotion.Stage.notch
    @State private var contentHeight: CGFloat = 0
    @State private var contentVisible = false
    @State private var motion: Task<Void, Never>?
    @State private var replyStart = Date()
    @State private var popover: IslandPopoverKind?
    @State private var cancelled = false
    @State private var cancelledTask: Task<Void, Never>?
    @State private var attachNote: String?
    @State private var attachNoteTask: Task<Void, Never>?
    /// The message whose rich answer is open under the island (16m-1).
    @State private var openAnswer: UUID?
    /// The job whose checklist was waved away (16m-2), keyed by its start.
    @State private var dismissedChecklist: Date?

    /// Incredible stacks the latest few; more is the window's job.
    static let maxResults = 3

    public init(
        chat: ChatViewModel, voice: VoiceViewModel, hold: HoldSettingsModel,
        geometry: IslandGeometry = IslandGeometry(),
        onShowMain: @escaping () -> Void,
        onSize: @escaping (IslandState.Size, CGFloat) -> Void,
        onReleaseKey: @escaping () -> Void = {},
        grabber: (any RegionGrabbing)? = nil
    ) {
        self.chat = chat
        self.voice = voice
        self.hold = hold
        self.geometry = geometry
        self.onShowMain = onShowMain
        self.onSize = onSize
        self.onReleaseKey = onReleaseKey
        self.grabber = grabber
    }

    private var state: IslandState {
        IslandState.from(
            chat.session.projection, pebbleHidden: hold.pebbleHidden,
            mainInFront: hold.mainInFront, holdLearned: hold.holdLearned,
            keyListening: hold.granted, debugTranscripts: chat.debugTranscripts,
            composing: IslandComposing.active(
                focused: fieldFocused, draft: draft, confirmingClear: confirmingClear,
                staged: chat.pendingAttachments.count, mainInFront: hold.mainInFront),
            cancelled: cancelled, followUp: chat.followUp, dropping: geometry.dropping)
    }

    /// Newest first, the replies of this conversation only, each keyed by
    /// its message so a card keeps its identity as newer ones push it down.
    static func resultRows(_ messages: [ChatMessage], limit: Int) -> [(id: UUID, result: IslandResult)] {
        messages.reversed()
            .filter { $0.role == .assistant && !$0.isStatus }
            .compactMap { message in IslandResult(reply: message.text).map { (id: message.id, result: $0) } }
            .prefix(limit)
            .map { $0 }
    }

    private var results: [(id: UUID, result: IslandResult)] {
        Self.resultRows(chat.messages, limit: Self.maxResults)
    }

    /// The newest reply, the one the panel says in big words.
    private var latestReply: ChatMessage? {
        chat.messages.last { $0.role == .assistant && !$0.isStatus }
    }

    public var body: some View {
        let state = self.state
        let notch = geometry.notch
        ZStack(alignment: .top) {
            silhouette(state)
            content(state)
                .frame(width: IslandChrome.width(for: state.size, notch: notch))
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: IslandSizeKey.self, value: geometry.size.height)
                })
                .modifier(contentMove)
                .frame(width: shown.width, height: shown.height, alignment: .top)
                .clipShape(NotchShape(width: shown.width, height: shown.height, radius: radius(notch)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "islandCanvas")
        .overlay(alignment: .top) { answerLayer }
        .overlayPreferenceValue(IslandPortalKey.self) { items in
            GeometryReader { proxy in portalLayer(items, in: proxy) }
        }
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(IslandSizeKey.self) { height in
            contentHeight = height
            onSize(state.size, height)
            // A resize while open follows the content with phase 2's spring.
            guard stage == .full else { return }
            withAnimation(reduceMotion ? nil : IslandMotion.secondSpring.animation) {
                shown = IslandChrome.shapeSize(for: state.size, contentHeight: height, notch: notch)
            }
        }
        .onChange(of: state.size, initial: true) { old, size in
            onSize(size, contentHeight)
            move(from: old == size ? .pebble : old, to: size)
        }
        .onChange(of: geometry.notch) { _, _ in move(from: state.size, to: state.size) }
        .onChange(of: geometry.peeking) { _, _ in peek(state) }
        .onChange(of: latestReply?.id) { _, _ in replyStart = Date() }
        .onChange(of: state.approval?.requestId, initial: true) { _, id in
            clickGuard = id == nil ? nil : ApprovalClickGuard(shownAt: Date().timeIntervalSince1970)
            if state.yieldsKeyboard { dismissField() }
        }
        .onChange(of: chat.session.projection.kind) { _, kind in
            // A release that sent something is the hold, learned.
            if kind == .processing(.pending), !hold.holdLearned { hold.holdLearned = true }
            // Speaking to it is continuing it: from here on the task is simply
            // the conversation, and the tag has done its job.
            if kind != .idle, kind != .hover, chat.followUp != nil { chat.followUp = nil }
        }
        .onAppear {
            geometry.onDrop = { urls, zone in attachActions.drop(urls, zone: zone) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandResignedKey)) { _ in
            // Another app took the keyboard: the field is done, the panel rests.
            fieldFocused = false
        }
    }

    /// The rich answer under the shape (16m-1): a card's "Ver" opens it, ×
    /// or Escape closes it, and its frame joins the click area the way the
    /// dropdown's does. It dies with its message and with the island's rest.
    @ViewBuilder
    private var answerLayer: some View {
        if let id = openAnswer,
           let message = chat.messages.first(where: { $0.id == id })
        {
            let blocks = AnswerBlocks.blocks(from: message.text)
            AnswerPopupView(
                blocks: blocks,
                // The notch sits centered on its screen, so twice its midX
                // IS the screen width the 76 % cap wants.
                screenWidth: geometry.notch.midX * 2,
                maxHeight: IslandChrome.canvasHeight - shown.height
                    - AnswerPopupMetrics.dropGap - IslandChrome.shadowRoom
                    - AnswerPopupMetrics.chrome,
                onClose: closeAnswer)
                .offset(y: shown.height + AnswerPopupMetrics.dropGap)
                .onGeometryChange(for: CGRect.self, of: { proxy in
                    proxy.frame(in: .named("islandCanvas"))
                }, action: { frame in
                    // A report landing during the close fade must not
                    // resurrect the click area (security review 16m).
                    guard openAnswer != nil else { return }
                    geometry.answer = frame.intersection(CGRect(
                        x: 0, y: 0, width: IslandChrome.canvasWidth,
                        height: IslandChrome.canvasHeight))
                })
                .onDisappear { geometry.answer = nil }
                .transition(.islandPopover(anchor: .top, reduceMotion: reduceMotion))
        }
    }

    private func closeAnswer() {
        withAnimation(.expoOut(IslandMotionBudget.popover.openDuration)) { openAnswer = nil }
        // Not waiting for the fade, same rule as the dropdown: the click
        // area shrinks with the decision.
        geometry.answer = nil
    }

    /// "Ver" earns a popup only when the reply holds more than the card
    /// already says (D2, spec 16m §5); a short answer keeps opening the
    /// window, which shows the same thing bigger.
    private func openResult(_ id: UUID) {
        guard let message = chat.messages.first(where: { $0.id == id }),
              AnswerBlocks.isRich(AnswerBlocks.blocks(from: message.text))
        else {
            onShowMain()
            return
        }
        withAnimation(.expoOut(IslandMotionBudget.popover.openDuration)) { openAnswer = id }
    }

    /// Tooltips and dropdowns over the clip (16o-1), kept off the notch band.
    private func portalLayer(_ items: [PortalItem], in proxy: GeometryProxy) -> some View {
        let canvas = proxy.size
        let notch = geometry.notch
        let band = CGRect(x: canvas.width / 2 - notch.width / 2, y: 0, width: notch.width, height: notch.height)
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.request.id) { item in
                let anchor = proxy[item.anchor]
                switch item.request {
                case .tooltip(let text):
                    PortalPlaced(anchor: anchor, canvas: canvas, forbidden: band) {
                        IslandTooltipBubble(text: text)
                    }
                    .transition(.opacity)
                case .popover(let kind):
                    PortalPlaced(anchor: anchor, canvas: canvas, forbidden: band, prefers: .below,
                                 align: .leading, onFrame: { rect in
                        geometry.portal = PortalFrame.next(
                            current: geometry.portal, report: rect, from: kind, active: popover)
                    }) {
                        IslandPopover {
                            switch kind {
                            case .menu:
                                IslandMenuList { picked in
                                    popover = nil
                                    choose(picked)
                                }
                            case .volume:
                                IslandVolumeControl(onChange: voice.setVolume)
                            case .attach:
                                IslandAttachList { picked in
                                    popover = nil
                                    pickAttach(picked)
                                }
                            }
                        }
                    }
                    .transition(.islandPopover(anchor: .topLeading, reduceMotion: reduceMotion))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Every path that opens or closes it (button, pick, Escape, the
        // panel closing) animates, so the transition plays.
        .animation(.expoOut(IslandMotionBudget.popover.openDuration), value: popover)
    }

    /// Panel reveal under the shape: rises 4 pt with a blur that clears (§9).
    private var contentMove: IslandMoveModifier {
        let move = IslandMotionBudget.contentIn.resolved(reduceMotion: reduceMotion)
        return IslandMoveModifier(
            opacity: contentVisible ? 1 : 0, blur: contentVisible ? 0 : move.blur,
            offset: contentVisible ? 0 : move.offset)
    }

    /// The black shape that continues the notch. At rest it is the notch,
    /// and holding it with the mouse is holding the key.
    private func silhouette(_ state: IslandState) -> some View {
        let notch = geometry.notch
        let resting = IslandMotion.rests(state.size)
        return NotchShape(width: shown.width, height: shown.height, radius: radius(notch))
            .fill(IslandInk.panel)
            // Incredible's hairline: a 12 % white edge once the island opens.
            .overlay(NotchShape(width: shown.width, height: shown.height, radius: radius(notch))
                .stroke(IslandInk.rim, lineWidth: Stroke.hairline)
                .opacity(resting ? 0 : 1))
            .shadow(color: IslandInk.shadow.opacity(
                IslandChrome.shadowOpacity(resting: resting, peeking: geometry.peeking)),
                radius: Space.x4, y: Space.x2)
            .contentShape(NotchShape(width: shown.width, height: shown.height, radius: radius(notch)))
            .gesture(resting || IslandState.acceptsPointer(size: state.size, pointerDown: pointer.isDown)
                ? holdGesture : nil)
            .accessibilityLabel(Localized.string("island.pebble"))
    }

    /// The peek keeps the notch's corners; only the open panel rounds out.
    private func radius(_ notch: Notch) -> CGFloat {
        shown.height > IslandChrome.peekSize(notch: notch).height ? NotchShape.openRadius : NotchShape.restRadius
    }

    /// The resting notch leans toward the pointer and back, with its shadow.
    private func peek(_ state: IslandState) {
        guard IslandMotion.rests(state.size), stage == .notch else { return }
        let notch = geometry.notch
        let target = geometry.peeking ? IslandChrome.peekSize(notch: notch)
            : CGSize(width: notch.width, height: notch.height)
        withAnimation(reduceMotion ? .expoOut(MotionTime.fast) : MotionSpring.islandPeek.animation) {
            shown = target
        }
    }

    /// Shape first, content after; closing, content first (spec 16f §2.5).
    private func move(from: IslandState.Size, to: IslandState.Size) {
        motion?.cancel()
        let notch = geometry.notch
        let steps = IslandMotion.steps(from: from, to: to, reduceMotion: reduceMotion)
        let reopens = IslandMotion.rests(from) != IslandMotion.rests(to)
        if !IslandPopoverToggle.survives(size: to) {
            popover = nil
            // Not waiting for the fade: the click area shrinks with the decision.
            geometry.portal = nil
            // The rich answer dies with the island's rest by the same rule.
            openAnswer = nil
            geometry.answer = nil
        }
        if reopens || IslandMotion.rests(to) {
            withAnimation(reduceMotion ? nil : .expoOut(IslandMotion.closeFade)) {
                contentVisible = false
            }
        }
        let contentAt = IslandMotion.contentStart(from: from, to: to, reduceMotion: reduceMotion)
        motion = Task { @MainActor in
            var clock = 0.0
            for step in steps {
                if step.delay > clock {
                    do { try await Task.sleep(for: .seconds(step.delay - clock)) } catch { return }
                    clock = step.delay
                }
                let target = IslandChrome.shapeSize(for: to, contentHeight: contentHeight, notch: notch)
                // Closing under a pointer that is still there lands on the peek.
                let resting = step.stage == .notch && geometry.peeking
                    ? IslandChrome.peekSize(notch: notch) : nil
                withAnimation(step.curve.animation) {
                    shown = resting ?? IslandChrome.size(of: step.stage, target: target, notch: notch, from: shown)
                }
                stage = step.stage
            }
            guard !IslandMotion.rests(to), !contentVisible else { return }
            if contentAt > clock {
                do { try await Task.sleep(for: .seconds(contentAt - clock)) } catch { return }
            }
            withAnimation(IslandMotionBudget.contentIn.animation(reduceMotion: reduceMotion)) {
                contentVisible = true
            }
        }
    }

    @ViewBuilder
    private func content(_ state: IslandState) -> some View {
        switch state.size {
        case .hidden, .pebble:
            EmptyView()
        case .nudge:
            shell(state, header: AnyView(IslandHeaderControls(popover: $popover))) { composer(state) }
        case .bar, .card:
            shell(state) { status(state) }
        }
    }

    /// The mark in the field row: the one place a mouse hold starts.
    private var mark: some View {
        Orb(state: .idle, levels: voice.levels, accentColor: Semantic.accent)
            .frame(width: IslandFieldMetrics.orb, height: IslandFieldMetrics.orb)
            .gesture(holdGesture)
            .accessibilityLabel(Localized.string("island.pebble"))
    }

    /// Mouse down is a press; up before the threshold is a tap that also
    /// summons the main window. The same classifier as the key.
    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pointer.down(at: Date().timeIntervalSince1970) == .pressed {
                    chat.session.send(.pressed)
                }
            }
            .onEnded { _ in
                switch pointer.up(at: Date().timeIntervalSince1970) {
                case .tapped:
                    chat.session.send(.tapped)
                    onShowMain()
                case .released:
                    chat.session.send(.released)
                case .cancelled:
                    chat.session.send(.holdCancelled)
                case .confirmed:
                    chat.session.send(.holdConfirmed)
                case .pressed, nil:
                    break
                }
            }
    }

    /// The band beside the notch holds the task slots; the rest sits under it.
    private func shell<Inner: View>(_ state: IslandState, header: AnyView? = nil,
                                    @ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack {
                if let header { header }
                Spacer(minLength: Space.none)
                if state.size != .bar {
                    IslandSlots(active: chat.session.projection.job != nil)
                }
            }
            .frame(height: geometry.notch.height)
            inner()
        }
        .padding(.horizontal, Space.x4)
        .padding(.bottom, Space.x4)
    }

    private func composer(_ state: IslandState) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            IslandComposer(
                draft: $draft, focused: $fieldFocused, mark: AnyView(mark),
                onSend: submit, popover: $popover, staged: !chat.pendingAttachments.isEmpty)
                .onExitCommand {
                    switch IslandEscape.action(popoverOpen: popover != nil) {
                    case .closePopover: popover = nil
                    case .dismissField: dismissField()
                    }
                }
            if !chat.pendingAttachments.isEmpty, !hold.mainInFront {
                IslandStagedRow(refs: chat.pendingAttachments, onRemove: chat.removePending)
            }
            if let attachNote {
                caption(attachNote)
            } else if case .none = state.line {} else {
                caption(IslandCopy.line(state.line))
            }
            if confirmingClear {
                IslandClearConfirm(onClear: clearHistory, onCancel: { confirmingClear = false })
            }
            reply(state)
            ForEach(Array(results.dropFirst().enumerated()), id: \.element.id) { index, row in
                IslandResultCard(result: row.result, onOpen: { openResult(row.id) })
                    .modifier(IslandLineReveal(index: index))
            }
        }
    }

    @ViewBuilder
    private func reply(_ state: IslandState) -> some View {
        if let latest = latestReply {
            let text = IslandReplyText.spoken(from: latest.text)
            if !text.isEmpty {
                IslandReply(text: text, startedAt: replyStart, speaking: state.meter == .agent)
                    .onTapGesture { openResult(latest.id) }
            }
        }
    }

    @ViewBuilder
    private func status(_ state: IslandState) -> some View {
        if state.line == .dropZones {
            IslandDropZones(zone: geometry.dropZone)
        } else if case .followUp(let title) = state.line {
            IslandFollowUpRow(title: title, onDrop: { chat.followUp = nil })
        } else if let notice = IslandNotice.content(for: state.line) {
            IslandNoticeCard(content: notice, onAction: perform,
                             onDismiss: { chat.session.send(.noticeExpired) })
        } else {
            statusRows(state)
        }
    }

    private func statusRows(_ state: IslandState) -> some View {
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
                        .buttonStyle(IslandChipStyle())
                }
                if IslandStop.asChip(state) {
                    Button(Localized.string("island.stop")) { stop() }
                        .buttonStyle(IslandChipStyle())
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
            let touched = chat.session.projection.touched
            if !touched.isEmpty, state.approval == nil {
                IslandReel(touched: touched)
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

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(GeistFont.uiCaption)
            .foregroundStyle(IslandInk.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func meter(_ state: IslandState) -> some View {
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

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !chat.pendingAttachments.isEmpty else { return }
        chat.draft = text
        chat.send()
        draft = ""
        dismissField()
    }

    private func dismissField() {
        fieldFocused = false
        onReleaseKey()
    }

    private var attachActions: IslandAttachActions {
        IslandAttachActions(chat: chat, voice: voice, grabber: grabber, say: sayAttach)
    }

    private func pickAttach(_ item: IslandAttachItem) {
        switch item {
        case .chooseFile:
            // The picker lives in the window: activating the app is
            // CompanionMain's call, never the island's (conformance 12d).
            onShowMain()
            NotificationCenter.default.post(name: .companionAttach, object: nil)
        case .screenshot:
            Task { await attachActions.screenshot() }
        case .captureText:
            Task {
                guard let text = await attachActions.captureText() else { return }
                draft = IslandDraft.appending(text, to: draft)
            }
        }
    }

    /// One line under the field for a few seconds, then the usual caption.
    private func sayAttach(_ text: String) {
        attachNoteTask?.cancel()
        attachNote = text
        attachNoteTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(IslandAttachMetrics.noteSeconds)) } catch { return }
            attachNote = nil
        }
    }

    private func choose(_ item: IslandMenuItem) {
        switch item {
        case .settings, .shortcuts:
            onShowMain()
            NotificationCenter.default.post(
                name: .companionOpenSettings,
                object: item == .shortcuts ? SettingsTab.general.rawValue : nil)
        case .openWindow:
            onShowMain()
        case .feedback:
            if let url = IslandCopy.feedbackURL { openURL(url) }
        case .clearHistory:
            confirmingClear = true
        }
    }

    /// The thread leaves the island; the conversation stays archived in
    /// Conversations, as a new conversation always leaves it.
    private func clearHistory() {
        confirmingClear = false
        chat.newConversation()
    }

    private func perform(_ action: IslandState.Action) {
        switch action {
        case .openKeys:
            onShowMain()
            NotificationCenter.default.post(name: .companionOpenSettings, object: SettingsTab.privacy.rawValue)
        case .openPermission(let failure):
            if let link = VoiceCopy.settingsLink(for: failure) { openURL(link) }
        case .stopHands:
            NotificationCenter.default.post(name: .companionStopHands, object: nil)
        case .openApps(let slug):
            // Same road as .openKeys: the window is the main's to raise,
            // the island only names the page and the app it means.
            onShowMain()
            NotificationCenter.default.post(name: .companionOpenApps, object: slug)
        }
    }

    private var iconSwap: AnyTransition {
        let swap = IslandMotionBudget.iconSwap
        return reduceMotion ? .opacity
            : .scale(scale: swap.fromScale).combined(with: .opacity)
                .combined(with: .modifier(active: IslandMoveModifier(opacity: 1, blur: swap.blur, offset: 0),
                                          identity: IslandMoveModifier(opacity: 1, blur: 0, offset: 0)))
    }

    /// Stop is the job's brake when one runs; otherwise it is the session's.
    /// Either way the island says so, briefly, as Incredible's pill does.
    private func stop() {
        if chat.session.projection.job != nil {
            chat.cancelJob()
        } else {
            chat.session.send(.stop)
        }
        cancelledTask?.cancel()
        cancelled = true
        cancelledTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(IslandStop.cancelledFor)) } catch { return }
            cancelled = false
        }
    }
}

public extension Notification.Name {
    /// The island panel resigned key (Code review 16, HIGH).
    static let islandResignedKey = Notification.Name("companion.islandResignedKey")
}

private struct IslandSizeKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Words for the island, ours, from the catalog.
enum IslandCopy {
    static func line(_ line: IslandState.Line) -> String {
        switch line {
        case .none: ""
        case .holdHint: Localized.string("island.hint")
        case .keyBlocked: Localized.string("island.keyBlocked")
        case .pending: Localized.string("island.pending")
        case .thinking: Localized.string("island.thinking")
        case .acting(let targets): ParentToolCopy.acting(targets, Localized.language())
        case .speaking: Localized.string("island.speaking")
        case .job(let goal, _, let steps):
            // "0 steps" is noise: the count appears once there is one.
            (goal ?? Localized.string("island.job")) + (steps == 0 ? "" : " · "
                + String(format: Localized.string(steps == 1 ? "island.job.step" : "island.job.steps"), steps))
        case .completed: Localized.string("island.completed")
        case .couldntHear: Localized.string("island.couldntHear")
        case .permission(let failure), .failure(let failure): VoiceCopy.failure(failure)
        case .dictating(let app): String(format: Localized.string("island.dictating"), app)
        case .pasting: Localized.string("island.pasting")
        case .dictated(let app): String(format: Localized.string("island.dictated"), app)
        case .transcriptsDebug: Localized.string("debug.transcriptsOn")
        case .cancelled: Localized.string("island.cancelled")
        case .followUp(let title): title
        case .dropZones: Localized.string("island.drop.title")
        case .connectApp(_, let name):
            String(format: Localized.string("island.connectApp"), name)
        }
    }

    static func action(_ action: IslandState.Action) -> String {
        switch action {
        case .openKeys: Localized.string("island.action.keys")
        case .openPermission: Localized.string("permission.open")
        case .stopHands: Localized.string("island.hands.stop")
        case .openApps: Localized.string("island.connectApp.action")
        }
    }

    /// A new message in the user's own mail app: no server of ours, no
    /// address sent anywhere until the user writes and sends it.
    static var feedbackURL: URL? {
        URL(string: "mailto:?subject=" + (Localized.string("island.feedback.subject")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Companion"))
    }

    /// The kind of line, not its words: what decides a swap (code review 16f-2).
    static func swapKey(_ line: IslandState.Line) -> String {
        switch line {
        case .permission(let failure), .failure(let failure): "failure-\(failure)"
        case .job: "job"
        case .acting: "acting"
        case .dictating: "dictating"
        case .dictated: "dictated"
        default: "\(line)"
        }
    }

    static func shimmers(_ line: IslandState.Line) -> Bool {
        switch line {
        case .pending, .thinking, .acting, .pasting: true
        default: false
        }
    }
}
