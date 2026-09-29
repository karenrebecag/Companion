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
    /// The message whose rich answer is open under the island (16m-1).
    @State var openAnswer: UUID?
    /// The job whose checklist was waved away (16m-2), keyed by its start.
    @State var dismissedChecklist: Date?

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

    var state: IslandState {
        IslandState.from(
            chat.session.projection, pebbleHidden: hold.pebbleHidden,
            mainInFront: hold.mainInFront, holdLearned: hold.holdLearned,
            keyListening: hold.granted, debugTranscripts: chat.debugTranscripts,
            composing: IslandComposing.active(
                focused: fieldFocused, draft: draft, confirmingClear: confirmingClear,
                staged: chat.pendingAttachments.count, mainInFront: hold.mainInFront),
            cancelled: cancelled, followUp: chat.followUp, dropping: geometry.dropping,
            errorText: ChatErrorSurface.visible(
                errorText: chat.errorText, needsOnboarding: chat.needsOnboarding,
                dismissed: chat.dismissedIslandError))
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

    var results: [(id: UUID, result: IslandResult)] {
        Self.resultRows(chat.messages, limit: Self.maxResults)
    }

    /// The newest reply, the one the panel says in big words.
    var latestReply: ChatMessage? {
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
        .onChange(of: chat.session.projection.notice, initial: true) { _, notice in
            chat.supersedeIslandError(notice: notice)
        }
        .onChange(of: chat.errorText) { _, _ in
            chat.supersedeIslandError(notice: chat.session.projection.notice)
        }
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

    @ViewBuilder
    func content(_ state: IslandState) -> some View {
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
    var mark: some View {
        Orb(state: .idle, levels: voice.levels, accentColor: Semantic.accent)
            .frame(width: IslandFieldMetrics.orb, height: IslandFieldMetrics.orb)
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

    /// The band beside the notch holds the task slots; the rest sits under it.
    func shell<Inner: View>(_ state: IslandState, header: AnyView? = nil,
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

    func composer(_ state: IslandState) -> some View {
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
    func reply(_ state: IslandState) -> some View {
        if let latest = latestReply {
            let text = IslandReplyText.spoken(from: latest.text)
            if !text.isEmpty {
                IslandReply(text: text, startedAt: replyStart, speaking: state.meter == .agent)
                    .onTapGesture { openResult(latest.id) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Localized.string("island.reply.open"))
                    .accessibilityAction { openResult(latest.id) }
            }
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
        dismissField()
    }

    func dismissField() {
        fieldFocused = false
        onReleaseKey()
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
