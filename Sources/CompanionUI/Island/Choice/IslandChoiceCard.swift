import CompanionCore
import SwiftUI

/// The question card (16m-6): the question, then one tile per option. A pick
/// only calls `onChoose` with the label; the chat sends it like a typed
/// message, so the card can never do more than she could by typing.
struct IslandChoiceCard: View {
    let block: ChoiceBlock
    /// Read live (never captured): the thread's verdict and what waits
    /// behind the running turn, so a digit after a click sees the click.
    let resolution: () -> ChoiceBlock.Resolution
    let queued: () -> [String]
    /// True when the label really went out (no key yet, or empty, is false).
    let onChoose: (String) -> Bool
    /// Told when the card gains or loses the keyboard, so the island does
    /// not fold away under it.
    let onFocus: (Bool) -> Void
    @State private var choice = IslandChoiceState()
    @State private var cursor: Int?
    @State private var listHeight: CGFloat = 0
    @FocusState private var focused: Bool

    private var effective: ChoiceBlock.Resolution {
        choice.effective(resolution: resolution(), queued: queued())
    }

    var body: some View {
        IslandChoiceWidth {
            VStack(alignment: .leading, spacing: IslandChoiceMetrics.gap) {
                Text(block.question)
                    .font(GeistFont.uiLabel.weight(.semibold))
                    .foregroundStyle(IslandInk.text)
                    .fixedSize(horizontal: false, vertical: true)
                optionList
            }
            .padding(.vertical, IslandChoiceMetrics.paddingY)
            .padding(.horizontal, IslandChoiceMetrics.paddingX)
            .background(RoundedRectangle(cornerRadius: IslandInk.cardRadius).fill(IslandInk.field))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(block.question)
        .accessibilityHint(Localized.string("island.choice.hint"))
        .focusable(effective == .open)
        .focusEffectDisabled()
        .focused($focused)
        // The cursor is the visible focus: it lands on the first option when
        // the card takes the keyboard, and the digits only act while it shows.
        .onChange(of: focused) { _, now in
            cursor = now ? (cursor ?? 0) : nil
            onFocus(now)
        }
        // Leaving the screen with the keyboard sends no focus change.
        .onDisappear { onFocus(false) }
        .onReceive(NotificationCenter.default.publisher(for: .islandResignedKey)) { _ in
            focused = false
        }
        .onKeyPress(phases: .down) { press in keyPressed(press) }
        // The card takes the keyboard only when she asks (a click on it or
        // Tab): grabbing it on appear would steal what she is typing.
        .onTapGesture { if effective == .open { focused = true } }
    }

    /// Hugs a short list; scrolls past the cap. Same measure-then-branch as
    /// the answer popup: a greedy ScrollView would make every card cap-tall.
    @ViewBuilder
    private var optionList: some View {
        if listHeight > IslandChoiceMetrics.listMaxHeight {
            ScrollView(.vertical) { options }
                .scrollIndicators(.never)
                .frame(height: IslandChoiceMetrics.listMaxHeight)
        } else {
            options
        }
    }

    private var options: some View {
        let now = effective
        return VStack(spacing: Space.x2) {
            ForEach(Array(block.options.enumerated()), id: \.offset) { index, option in
                AnswerOption(
                    index: index, title: option.label, detail: option.detail,
                    state: IslandChoiceState.tile(index: index, resolution: now, cursor: cursor),
                    accessibility: IslandChoiceCopy.optionAccessibility(
                        index: index, count: block.options.count,
                        label: option.label, resolution: now),
                    action: { pick(index) })
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { listHeight = $0 }
    }

    private func pick(_ index: Int) {
        choice.pick(index, block: block, resolution: resolution(), queued: queued(), send: onChoose)
    }

    private func keyPressed(_ press: KeyPress) -> KeyPress.Result {
        guard effective == .open, cursor != nil,
              let key = Self.key(of: press)
        else { return .ignored }
        switch IslandChoiceKeys.outcome(for: key, focused: cursor, count: block.options.count) {
        case .none: return .ignored
        case .focus(let index): cursor = index
        case .choose(let index): pick(index)
        }
        return .handled
    }

    private static func key(of press: KeyPress) -> IslandChoiceKeys.Key? {
        let named: IslandChoiceKeys.Named = switch press.key {
        case .upArrow: .up
        case .downArrow: .down
        case .return: .enter
        default: .other
        }
        return IslandChoiceKeys.key(named, characters: press.characters, hasModifiers: !press.modifiers.isEmpty)
    }
}

/// One choice: a quiet tile that turns indigo under the pointer, with its
/// shortcut number on the left. Rebuilt from the 16l primitive (retired by
/// 16p-2 while nothing drew it) on the shared island ink.
struct AnswerOption: View {
    let index: Int
    let title: String
    let detail: String?
    let state: IslandChoice.Tile
    let accessibility: String
    let action: () -> Void
    @State private var hovering = false

    private var lit: Bool { state == .picked || state == .cursor || (hovering && state == .idle) }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AnswerOptionMetrics.gap) {
                badge
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(title)
                        .font(GeistFont.uiLabel)
                        .foregroundStyle(IslandInk.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(GeistFont.uiCaption)
                            .foregroundStyle(IslandInk.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, AnswerOptionMetrics.paddingY)
            .padding(.horizontal, AnswerOptionMetrics.paddingX)
            .background(RoundedRectangle(cornerRadius: AnswerOptionMetrics.radius)
                .fill(lit ? IslandPalette.indigo.color.opacity(IslandChoiceTile.litFill) : IslandInk.chip))
            .overlay(RoundedRectangle(cornerRadius: AnswerOptionMetrics.radius)
                .strokeBorder(lit ? IslandPalette.indigo.color.opacity(IslandChoiceTile.litBorder) : IslandInk.hairline,
                              lineWidth: Stroke.hairline))
            .contentShape(RoundedRectangle(cornerRadius: AnswerOptionMetrics.radius))
            .opacity(state == .unavailable ? IslandChoiceMetrics.unavailableAlpha : 1)
        }
        .buttonStyle(.plain)
        // The pick stays crisp: `.disabled` would dim the very tile that
        // marks the answer. It is inert instead, and VoiceOver hears it selected.
        .disabled(state == .unavailable)
        .allowsHitTesting(state != .picked)
        .onHover { hovering = $0 }
        .animation(MotionCurve.animation(MotionCurve.standard, MotionTime.fast), value: lit)
        .accessibilityLabel(accessibility)
        .accessibilityValue(detail ?? "")
        .accessibilityAddTraits(state == .picked ? .isSelected : [])
    }

    private var badge: some View {
        ZStack {
            if state == .picked {
                Image(systemName: "checkmark")
            } else {
                Text(String(index + 1))
            }
        }
        .font(GeistFont.uiCaption.weight(.semibold))
        .foregroundStyle(IslandInk.text)
        .frame(width: IslandInk.slotSide, height: IslandInk.slotSide)
        .background(RoundedRectangle(cornerRadius: Radius.md)
            .fill(lit ? IslandPalette.indigo.color.opacity(IslandChoiceTile.badgeFill) : IslandInk.chip))
    }
}

/// Own values (the research measures the card, not the option's states).
enum IslandChoiceTile {
    static let litFill = 0.22
    static let litBorder = 0.4
    static let badgeFill = 0.42
}

/// Gives the card its 340-440 in whatever room the island leaves.
struct IslandChoiceWidth: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let card = subviews.first, proposal.width != 0 else { return .zero }
        let ideal = card.sizeThatFits(.unspecified).width
        let width = IslandChoiceMetrics.width(
            available: proposal.width ?? IslandChoiceMetrics.unbounded, ideal: ideal)
        return CGSize(width: width, height: card.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
