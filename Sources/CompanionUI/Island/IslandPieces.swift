import CompanionCore
import SwiftUI

/// Incredible's notch bar is black in light and dark alike: it reads as an
/// extension of the notch, not as a window of the theme (spec 16c §2).
enum IslandInk {
    // Arc's dark theme on black: opaque surfaces, so a control reads the
    // same over the island and over a result under it.
    static var panel: Color { Neutral.black.color }
    static var text: Color { ArcTone.foreground.color }
    static var secondary: Color { ArcTone.textSecondary.color }
    static var muted: Color { ArcTone.textMuted.color }
    static let chipSwatch = ArcTone.surface
    static let chipPressedSwatch = ArcTone.surfaceMuted
    static let hairlineSwatch = ArcTone.border
    static var chip: Color { chipSwatch.color }
    static var chipPressed: Color { chipPressedSwatch.color }
    static var field: Color { chipSwatch.color }
    /// The composer field and its idle send button, sampled from Incredible.
    static var fieldFill: Color { IslandFieldMetrics.fillSwatch.color }
    static var sendIdle: Color { IslandFieldMetrics.sendIdleSwatch.color }
    static var hairline: Color { hairlineSwatch.color }
    static var divider: Color { ArcTone.borderSubtle.color }
    static var rim: Color { white(IslandMetrics.rimAlpha) }
    /// Only the open panel casts one; at rest it is hardware.
    static var shadow: Color { Neutral.black.color.opacity(0.35) }
    static var amber: Color { ArcTone.warning.color }
    static var green: Color { ArcTone.success.color }
    static var destructive: Color { IslandPalette.error.color }
    static let radius: CGFloat = IslandMetrics.openRadius
    /// Arc: anything nested in the open island takes the concentric radius.
    static var cardRadius: CGFloat { IslandGrid.nestedRadius }
    static let lightSide: CGFloat = 8
    static let slotSide: CGFloat = 22
    static let sendSide: CGFloat = IslandMetrics.sendSide
    static let chipVertical: CGFloat = 6
    /// Arc's menus float on surface-raised, a step over what they open from.
    static let popoverSwatch = ArcTone.surfaceRaised
    static var popover: Color { popoverSwatch.color }
    /// Arc's tooltip is inverted: foreground fill, background text.
    static let tooltipSwatch = ArcTone.foreground
    static var tooltip: Color { tooltipSwatch.color }
    static var blue: Color { IslandPalette.accent.color }
    static var stop: Color { ArcTone.danger.color }

    private static func white(_ alpha: Double) -> Color { Neutral.white.color.opacity(alpha) }
    /// The countdown ring moves a few pixels a second; more frames buy nothing.
    static let ringFrame: Double = 1.0 / 15
}

/// Amber = it needs you, green = done. A dot, never a word.
struct IslandLight: View {
    let light: IslandState.Light
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let color {
                // Success check, small: it pops in with the one allowed bob.
                Circle()
                    .fill(color)
                    .frame(width: IslandInk.lightSide, height: IslandInk.lightSide)
                    .shadow(color: color.opacity(0.7), radius: IslandInk.lightSide / 2)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    .id(light)
                    .accessibilityLabel(Localized.string(
                        light == .amber ? "island.light.amber" : "island.light.green"))
            }
        }
        .animation(reduceMotion ? .expoOut(MotionTime.fast) : MotionSpring.success.animation, value: light)
    }

    private var color: Color? {
        switch light {
        case .none: nil
        case .amber: IslandInk.amber
        case .green: IslandInk.green
        }
    }
}

/// Incredible's field (16n, from the 20:13 screenshot): the orb outside, then
/// one rounded field that holds the words, the clip and send. Volume and the
/// menu live in the notch band (`IslandHeaderControls`); their popovers drop
/// from there through the portal (16o-1).
struct IslandComposer: View {
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let mark: AnyView
    let onSend: () -> Void
    /// The clip opens its dropdown through the portal, like the header's (16i-2).
    @Binding var popover: IslandPopoverKind?
    /// A staged attachment is enough to send, as in the window.
    var staged = false
    /// The `@` selector: it takes the arrows, Tab and the Return that would send.
    var mentions: MentionSelectorModel?

    var body: some View {
        HStack(spacing: IslandFieldMetrics.orbGap) {
            mark.islandTooltip(Localized.string("island.tip.talk"))
            field
        }
    }

    private var field: some View {
        HStack(spacing: Space.none) {
            TextField(Localized.string("island.ask"), text: $draft)
                .textFieldStyle(.plain)
                .font(Fonts.geist(TypeSize.rowTitle))
                .foregroundStyle(IslandInk.text)
                .focused(focused)
                // Return picks the row while the selector is open; the key
                // handler below leaves it out so a pick never also sends.
                .onSubmit { if mentions?.press(.enter) != true { onSend() } }
                .onKeyPress(keys: [.upArrow, .downArrow, .tab, .rightArrow, .leftArrow], phases: .down) { press in
                    guard press.modifiers.isEmpty, let key = Self.mentionKey(press.key),
                          mentions?.press(key) == true else { return .ignored }
                    return .handled
                }
                .padding(.leading, IslandFieldMetrics.textInset)
            IconButton("paperclip", label: Localized.string("island.attach"), size: .island,
                       tone: .island, active: popover == .attach) {
                popover = IslandPopoverToggle.next(current: popover, tapped: .attach)
            }
            .portal(popover == .attach ? .popover(.attach) : nil)
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(Fonts.geist(TypeSize.body).weight(.medium))
                    .foregroundStyle(ready ? IslandInk.panel : IslandInk.muted)
                    .frame(width: IslandFieldMetrics.send, height: IslandFieldMetrics.send)
                    .background(Circle().fill(ready ? IslandInk.text : IslandInk.sendIdle))
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .islandTooltip(Localized.string("island.tip.send"))
            .accessibilityLabel(Localized.string("island.send"))
            .padding(.leading, Space.x1)
        }
        .padding(.trailing, IslandFieldMetrics.trailing)
        .frame(height: IslandFieldMetrics.height)
        .background(RoundedRectangle(cornerRadius: IslandFieldMetrics.radius).fill(IslandInk.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: IslandFieldMetrics.radius)
            .strokeBorder(IslandFieldMetrics.rimSwatch.color, lineWidth: Stroke.hairline))
    }

    private static func mentionKey(_ key: KeyEquivalent) -> MentionKeys.Key? {
        switch key {
        case .upArrow: .up
        case .downArrow: .down
        case .tab: .tab
        case .rightArrow: .right
        case .leftArrow: .left
        default: nil
        }
    }

    private var ready: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || staged }
}

/// The destructive entry asks once, inside the panel: a sheet or an alert
/// would need the window this panel never is.
struct IslandClearConfirm: View {
    let onClear: () -> Void
    let onCancel: () -> Void

    var body: some View {
        IslandMorphPill(rim: IslandMorphMetrics.askingEdgeSwatch.color) {
            Text(Localized.string("island.clear.ask"))
                .font(GeistFont.uiCaption.weight(.medium))
                .foregroundStyle(IslandInk.text)
                .lineLimit(1)
                .frame(maxWidth: IslandMorphMetrics.promptMaxWidth, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, IslandMorphMetrics.promptLeading)
                .padding(.trailing, Space.x1_5)
            ForEach(Self.answers(onClear: onClear, onCancel: onCancel), id: \.key) { answer in
                Button(Localized.string(answer.key), action: answer.action)
                    .buttonStyle(IslandMorphAction(role: answer.tone.map { .primary($0) } ?? .secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cancel comes first and stays plain; only the destructive answer is filled.
    static func answers(onClear: @escaping () -> Void, onCancel: @escaping () -> Void) -> [IslandMorphAnswer] {
        [IslandMorphAnswer(key: "island.clear.no", tone: nil, action: onCancel),
         IslandMorphAnswer(key: "island.clear.yes", tone: ArcTone.danger, action: onClear)]
    }
}

/// Wave 20d B: what ran without asking, with the one way back. The line is
/// the receipt and the button is the only door to the undo; the model has no
/// call that reaches it.
struct IslandReceiptRow: View {
    let receipt: UndoReceipt
    let onUndo: () -> Void

    var body: some View {
        // confirm-morph's done face: a success check, what ran, the way back.
        IslandMorphPill {
            HStack(spacing: IslandMorphMetrics.statusGap) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Fonts.symbol(IslandMorphMetrics.checkSide, weight: .medium))
                    .foregroundStyle(IslandInk.panel, ArcTone.success.color)
                    .accessibilityHidden(true)
                Text(IslandCopy.receipt(receipt))
                    .font(GeistFont.uiCaption.weight(.medium))
                    .foregroundStyle(IslandInk.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, Space.x1_5)
            .padding(.trailing, Self.offersUndo(receipt) ? Space.x1 : Space.x2)
            if Self.offersUndo(receipt) {
                Button(Localized.string("island.receipt.undo"), action: onUndo)
                    .buttonStyle(IslandMorphAction(role: .secondary))
            }
        }
    }

    /// The button is the only door to the undo, so it shows only when there is one.
    static func offersUndo(_ receipt: UndoReceipt) -> Bool { receipt.undo != nil }
}
