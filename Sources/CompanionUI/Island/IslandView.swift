import CompanionCore
import SwiftUI

/// The island (Wave 12b), Incredible's notch bar since 16e: the app lives
/// here — ask, see what it heard, see the results. Paints `IslandState`;
/// never decides the kind.
package struct IslandView: View {
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
    /// The clip's file picker (16m-3); absent, "Choose file…" says so.
    let pickFiles: IslandFilePicker?
    /// The release the checker found (16m-4); absent, the island never offers one.
    let updates: UpdateState?
    /// The `@` selector's sources (16m-7); absent, `@` is just a character.
    let mentions: MentionSelectorModel?
    /// Draws the popup's Mermaid diagrams (16m-5b); absent, they show as code.
    let diagrams: (any DiagramRendering)?
    /// Saves a diagram's PNG through the system's panel (16m-5b); absent, no download tool.
    let saveFile: IslandFileSaver?
    /// Where self-inspection reads the island (spec self-qa-inspeccion);
    /// absent, nothing is recorded.
    let mirror: InspectionMirror?
    // Members are internal, not private, on purpose: the island's families
    // extend this view from Island/*/IslandView+X.swift, and Swift's private
    // stops at the file.
    @Environment(\.openURL) var openURL
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var pointer = HoldKeyClassifier()
    @State var clickGuard: ApprovalClickGuard?
    @State var draft = ""
    @State var confirmingClear = false
    @FocusState var fieldFocused: Bool
    /// The shape as drawn right now; `IslandMotion` walks it to the target.
    @State var shown = CGSize.zero
    @State var stage = IslandMotion.Stage.notch
    @State var contentHeight: CGFloat = 0
    @State var contentVisible = false
    @State var motion: Task<Void, Never>?
    @State var replyStart = Date()
    @State var popover: IslandPopoverKind?
    @State var cancelled = false
    @State var cancelledTask: Task<Void, Never>?
    @State var attachNote: String?
    @State var attachNoteTask: Task<Void, Never>?
    /// Files the chat refused from the island, shown as cards in error (16m-3).
    @State var attachFailures: [IslandAttachFailure] = []
    /// The message whose rich answer is open under the island (16m-1).
    @State var openAnswer: UUID?
    /// The reply whose question card holds the keyboard, if any.
    @State var focusedChoiceID: UUID?
    /// The pointer is over the working island: the run card shows while it is.
    @State var hoveringWork = false
    /// Whether the latest result card was ever opened, for the model (16h-3).
    @State var resultAttention = IslandResultAttention()
    /// P3: the voice line chip, and the reply its quiet turn carries.
    @State var voiceLines = VoiceLineModel()
    @State var replyOfTurn: UUID?
    /// The orb is one piece in every state (Arc's now-playing): opening the
    /// island moves it to its new row instead of fading one out and another in.
    @Namespace var orbSpace

    /// Incredible stacks the latest few under the reply; more is the window's job.
    static let maxResults = 2

    package init(
        chat: ChatViewModel, voice: VoiceViewModel, hold: HoldSettingsModel,
        geometry: IslandGeometry = IslandGeometry(),
        onShowMain: @escaping () -> Void,
        onSize: @escaping (IslandState.Size, CGFloat) -> Void,
        onReleaseKey: @escaping () -> Void = {},
        grabber: (any RegionGrabbing)? = nil,
        pickFiles: IslandFilePicker? = nil,
        updates: UpdateState? = nil,
        mentions: MentionSources? = nil,
        diagrams: (any DiagramRendering)? = nil,
        saveFile: IslandFileSaver? = nil,
        mirror: InspectionMirror? = nil
    ) {
        self.chat = chat
        self.voice = voice
        self.hold = hold
        self.geometry = geometry
        self.onShowMain = onShowMain
        self.onSize = onSize
        self.onReleaseKey = onReleaseKey
        self.grabber = grabber
        self.pickFiles = pickFiles
        self.updates = updates
        self.mentions = mentions.map(MentionSelectorModel.init(sources:))
        self.diagrams = diagrams
        self.saveFile = saveFile
        self.mirror = mirror
    }

    var state: IslandState {
        Self.holdingChip(IslandState.from(
            chat.session.projection, pebbleHidden: hold.pebbleHidden,
            mainInFront: hold.mainInFront, holdLearned: hold.holdLearned,
            keyListening: hold.granted, debugTranscripts: chat.debugTranscripts,
            composing: IslandComposing.active(
                focused: fieldFocused, draft: draft, confirmingClear: confirmingClear,
                staged: chat.pendingAttachments.count + attachFailures.count,
                mainInFront: hold.mainInFront, picking: geometry.picking,
                choiceFocused: IslandChoice.isFocused(
                    focusedID: focusedChoiceID,
                    liveID: latestReply.flatMap { IslandChoice.block(in: $0) == nil ? nil : $0.id })),
            cancelled: cancelled, followUp: chat.followUp, dropping: geometry.dropping,
            errorText: ChatErrorSurface.visible(
                errorText: chat.errorText, needsOnboarding: chat.needsOnboarding,
                dismissed: chat.dismissedIslandError),
            update: updates?.noticeTag), chipMounted: voiceLines.line != nil)
    }

    /// What the panel says above a question card: the card already carries the
    /// question as its title, so the same words are shown once. Voice and
    /// typed turns both land here as the latest assistant message.
    static func replyText(for message: ChatMessage) -> String {
        let text = IslandReplyText.spoken(from: message.text)
        guard let choice = IslandChoice.block(in: message),
              IslandChoice.sameWords(text, choice.question)
        else { return text }
        return ""
    }

    /// The newest reply, the one the panel says in big words.
    var latestReply: ChatMessage? {
        chat.messages.last { $0.role == .assistant && !$0.isStatus }
    }

    package var body: some View {
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
                .frame(width: shown.width, height: shown.height, alignment: .top)
                // The content root exists for every open size, so a bare job
                // has a hover target; the run card is inside it and keeps it.
                // Only where the region exists: at pebble size it would sit
                // over the silhouette's notch hold gesture.
                .modifier(RunCardHoverRegion(
                    enabled: RunCardModel.hoverRegionExists(size: state.size),
                    hovering: $hoveringWork))
                .clipShape(NotchShape(width: shown.width, height: shown.height, radius: radius(notch)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "islandCanvas")
        .overlay(alignment: .top) { answerLayer }
        .overlay(alignment: .top) { voiceLineLayer }
        .overlayPreferenceValue(IslandPortalKey.self) { items in
            GeometryReader { proxy in portalLayer(items, in: proxy) }
        }
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(IslandSizeKey.self) { height in
            contentHeight = height
            onSize(state.size, height)
            // A resize while open follows the content: growing overshoots like opening, shrinking does not.
            guard stage == .full else { return }
            let target = IslandChrome.shapeSize(for: state.size, contentHeight: height, notch: notch)
            let curve = IslandMotion.resize(growing: IslandMotion.grows(from: shown, to: target))
            withAnimation(reduceMotion ? nil : curve.animation) {
                shown = target
            }
        }
        .onChange(of: state.size) { _, size in
            hoveringWork = RunCardModel.hoverAfterResize(raw: hoveringWork, newSize: size)
        }
        .onChange(of: state.size, initial: true) { old, size in
            onSize(size, contentHeight)
            move(from: old == size ? .pebble : old, to: size)
        }
        // The state this body painted, not one rebuilt from the session: the
        // mirror is plain storage, so writing it never repaints anything.
        .onChange(of: state, initial: true) { _, painted in mirror?.paint(painted) }
        .onChange(of: geometry.notch) { _, _ in move(from: state.size, to: state.size) }
        .onChange(of: chat.session.projection.notice, initial: true) { _, notice in
            chat.supersedeIslandError(notice: notice)
        }
        .onChange(of: chat.errorText) { _, _ in
            chat.supersedeIslandError(notice: chat.session.projection.notice)
        }
        .onChange(of: chat.messages.map(\.id)) { _, ids in
            guard let open = openAnswer else { return }
            openAnswer = IslandAnswerSignal.reconcile(
                open: open, messageExists: ids.contains(open), session: chat.session).open
            if openAnswer == nil { geometry.answer = nil }
        }
        .onChange(of: geometry.peeking) { _, _ in peek(state) }
        .onChange(of: latestReply?.id) { _, id in
            replyStart = Date()
            if state.reportsReplyShown { reportReplyShown(id) }
        }
        .onChange(of: state.approval?.requestId, initial: true) { _, _ in
            if state.yieldsKeyboard { dismissField() }
        }
        .onChange(of: clickGuardKey, initial: true) { _, _ in armClickGuard() }
        .onChange(of: chat.session.projection.kind) { _, kind in
            // A release that sent something is the hold, learned.
            if kind == .processing(.pending), !hold.holdLearned { hold.holdLearned = true }
            // Speaking to it is continuing it: from here on the task is simply
            // the conversation, and the tag has done its job.
            if kind != .idle, kind != .hover, chat.followUp != nil { chat.followUp = nil }
        }
        .onAppear {
            geometry.onDrop = { urls, zone in attachActions.drop(urls, zone: zone) }
            // No `self` in the closure: the model lives in this view, and a
            // closure holding the view would hold the model back.
            let chat = chat
            let words = $draft
            mentions?.onPick = { Self.applyMention($0, chat: chat, draft: words) }
        }
        .onChange(of: draft) { _, words in
            chat.syncMentions(with: words)
            mentions?.update(draft: words)
        }
        // The system's Contacts dialog takes the keyboard from the panel; the
        // island must not fold under it (same rule as the file picker).
        .onChange(of: mentions?.isRequestingAccess ?? false) { _, asking in geometry.picking = asking }
        .onReceive(NotificationCenter.default.publisher(for: .islandResignedKey)) { _ in
            // Another app took the keyboard: the field is done, the panel rests.
            fieldFocused = false
            focusedChoiceID = nil
        }
    }

    @ViewBuilder
    func content(_ state: IslandState) -> some View {
        switch state.size {
        case .hidden, .pebble:
            EmptyView()
        case .nudge:
            shell(state, header: AnyView(IslandHeaderControls(popover: $popover))) { composer(state) }
        case .bar, .card, .wideCard:
            shell(state) {
                IslandColumn(
                    maxHeight: IslandChrome.columnMaxHeight(bandHeight: geometry.notch.height),
                    anchorBottom: RunCardModel.anchorsColumnBottom(cardVisible: runCardShows(state))) {
                    status(state)
                }
            }
        }
    }

    /// The mark in the field row: the one place a mouse hold starts.
    var mark: some View {
        IslandVoiceOrb(state: IslandOrbState.composer(levels: voice.levels), levels: voice.levels,
                       size: IslandFieldMetrics.orb)
            .matchedGeometryEffect(id: IslandOrbTravel.id, in: orbSpace)
            .contentShape(Circle())
            .gesture(holdGesture)
            .accessibilityLabel(Localized.string("island.pebble"))
    }

    /// Mouse down is a press; up before the threshold is a tap that also
    /// summons the main window. The same classifier as the key.
    var holdGesture: some Gesture {
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

    /// The band beside the notch holds the header controls; the rest sits
    /// under it on the island's grid. A running task shows in its run, not
    /// as decorative slots in the band.
    func shell<Inner: View>(_ state: IslandState, header: AnyView? = nil,
                                    @ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: IslandChrome.shellSpacing) {
            HStack {
                if let header { header }
                Spacer(minLength: Space.none)
            }
            .frame(height: geometry.notch.height)
            .modifier(contentSlot(.field))
            inner()
        }
        .padding(.horizontal, IslandChrome.shellMargin)
        .padding(.bottom, IslandChrome.shellBottom)
    }

    func composer(_ state: IslandState) -> some View {
        VStack(alignment: .leading, spacing: IslandGrid.groupGap) {
            Group {
                IslandComposer(
                    draft: $draft, focused: $fieldFocused,
                    // The unpainted line rides on the orb, the one piece that
                    // stands for the voice here.
                    mark: AnyView(mark.accessibilityValue(
                        IslandCopy.voiceOverOnly(state.line) ? IslandCopy.line(state.line) : "")),
                    onSend: submit, popover: $popover, staged: !chat.pendingAttachments.isEmpty,
                    mentions: mentions)
                    .onExitCommand {
                        if mentions?.press(.escape) == true { return }
                        switch IslandEscape.action(popoverOpen: popover != nil) {
                        case .closePopover: popover = nil
                        case .dismissField: dismissField()
                        }
                    }
                // Everything under the field sits in the grid's content column,
                // under the words, not under the orb.
                Group {
                    if let mentions, mentions.isOpen { MentionSelectorView(model: mentions) }
                    attachTray
                    if let attachNote {
                        caption(attachNote)
                    } else if case .none = state.line {} else if let shown = IslandCopy.visibleLine(state.line) {
                        caption(shown)
                    }
                    if confirmingClear {
                        IslandClearConfirm(onClear: clearHistory, onCancel: { confirmingClear = false })
                    }
                }
                .islandContentColumn()
            }
            .modifier(contentSlot(.field))
            VStack(alignment: .leading, spacing: IslandGrid.groupGap) {
                thread(state)
            }
            .modifier(contentSlot(.conversation))
        }
    }

    @ViewBuilder
    func reply(_ state: IslandState) -> some View {
        if let latest = latestReply {
            let text = Self.replyText(for: latest)
            if !text.isEmpty {
                IslandLiveReply(voice: voice, text: text, startedAt: replyStart, speaking: state.meter == .agent)
                    .onTapGesture { openResult(latest.id) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Localized.string("island.reply.open"))
                    .accessibilityAction { openResult(latest.id) }
            }
            choiceCard(latest)
        } else {
            // A realtime reply reaches the thread only at transcript.done; until then the caption is all there is.
            IslandLiveReply(voice: voice, text: "", startedAt: replyStart, speaking: false)
        }
    }

    @ViewBuilder
    func choiceCard(_ latest: ChatMessage) -> some View {
        if let choice = IslandChoice.block(in: latest) {
            IslandChoiceCard(
                block: choice,
                resolution: { IslandChoice.resolution(of: choice, messageID: latest.id, in: chat.messages) },
                queued: { chat.queued },
                onChoose: { chat.choose($0) },
                onFocus: { gained in
                    if gained { focusedChoiceID = latest.id } else if focusedChoiceID == latest.id { focusedChoiceID = nil }
                })
                .id(latest.id)
        }
    }

    func caption(_ text: String) -> some View {
        Text(text)
            .font(GeistFont.uiCaption)
            .foregroundStyle(IslandInk.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !chat.pendingAttachments.isEmpty else { return }
        chat.draft = text
        chat.send()
        draft = ""
        attachFailures = []
        dismissField()
    }

    /// A pick from the selector: the words, the mention that now stands in
    /// them, and a file when the pick was one. A file that cannot be attached
    /// leaves neither its `@name` nor a mention behind.
    static func applyMention(_ pick: MentionPick, chat: ChatViewModel, draft: Binding<String>) {
        let result = pick.applied(attach: { chat.attach($0) != nil })
        draft.wrappedValue = result.draft
        if let mention = result.mention { chat.addMention(mention) }
    }

    func dismissField() {
        fieldFocused = false
        onReleaseKey()
    }
}

package extension Notification.Name {
    /// The island panel resigned key (Code review 16, HIGH).
    static let islandResignedKey = Notification.Name("companion.islandResignedKey")
}

private struct IslandSizeKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
