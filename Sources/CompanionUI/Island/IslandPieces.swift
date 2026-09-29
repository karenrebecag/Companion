import CompanionCore
import SwiftUI

/// Incredible's notch bar is black in light and dark alike: it reads as an
/// extension of the notch, not as a window of the theme (spec 16c §2).
enum IslandInk {
    // 16l-4: Incredible's `--ci-*` whites over black.
    static var panel: Color { Neutral.black.color }
    static var text: Color { white(IslandAlpha.text) }
    static var secondary: Color { white(IslandAlpha.secondary) }
    static var muted: Color { white(IslandAlpha.muted) }
    static var chip: Color { white(IslandAlpha.tile) }
    static var chipPressed: Color { white(IslandAlpha.tileHover) }
    static var field: Color { white(IslandAlpha.tile) }
    /// The composer field and its idle send button, sampled from Incredible.
    static var fieldFill: Color { white(IslandFieldMetrics.fill) }
    static var sendIdle: Color { white(IslandFieldMetrics.sendFill) }
    static var hairline: Color { white(IslandAlpha.border) }
    static var divider: Color { white(IslandAlpha.divider) }
    static var rim: Color { white(IslandMetrics.rimAlpha) }
    /// Only the open panel casts one; at rest it is hardware.
    static var shadow: Color { Neutral.black.color.opacity(0.35) }
    static var amber: Color { Accent.orange.color }
    static var green: Color { Palette.signalGreen.color }
    static var destructive: Color { IslandPalette.error.color }
    static let radius: CGFloat = IslandMetrics.openRadius
    static let cardRadius: CGFloat = AnswerOptionMetrics.radius
    static let lightSide: CGFloat = 8
    static let slotSide: CGFloat = 22
    /// A word not yet said: the secondary ink's weight on black.
    static let dimWord: Double = 0.62
    static let sendSide: CGFloat = IslandMetrics.sendSide
    static let barWidth: CGFloat = 3
    static let chipVertical: CGFloat = 6
    /// Incredible's dropdowns sit a step lighter than the panel they open from.
    static var popover: Color { Neutral.n800.color }
    /// Incredible's tooltip pill (16o research).
    static var tooltip: Color { Swatch("17181B").color }
    static var blue: Color { IslandPalette.accent.color }
    static var blueTile: Color { IslandPalette.accent.color.opacity(0.18) }
    static var stop: Color { Swatch("FF453A").color }

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

/// The listening pill: bars that follow the microphone, no status words.
struct IslandWaveBars: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let weights: [Double] = [0.45, 0.8, 1, 0.7, 0.4]
    private static let minHeight: CGFloat = 4
    private static let maxHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: IslandInk.barWidth) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .fill(IslandInk.text)
                    .frame(width: IslandInk.barWidth, height: height(Self.weights[index]))
            }
        }
        .frame(height: Self.maxHeight)
        .animation(reduceMotion ? nil : .expoOut(MotionTime.follow), value: level)
        .accessibilityHidden(true)
    }

    private func height(_ weight: Double) -> CGFloat {
        let live = min(max(level, 0), 1) * weight
        return Self.minHeight + (Self.maxHeight - Self.minHeight) * CGFloat(live)
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
                    .font(Fonts.geist(TypeSize.body).weight(.semibold))
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
        HStack(spacing: Space.x2) {
            Text(Localized.string("island.clear.ask"))
                .font(GeistFont.uiCaption)
                .foregroundStyle(IslandInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(Localized.string("island.clear.no"), action: onCancel)
                .buttonStyle(CapsuleChipStyle(ink: .island, density: .compact))
            Button(Localized.string("island.clear.yes"), action: onClear)
                .buttonStyle(CapsuleChipStyle(ink: .islandDestructive, density: .compact))
        }
    }
}

/// Where running tasks sit, top right (16f): three slots, the first one
/// turning while a job runs.
struct IslandSlots: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        HStack(spacing: Space.x2) {
            ForEach(0..<3, id: \.self) { index in
                ZStack {
                    Circle()
                        .strokeBorder(IslandInk.secondary, style: StrokeStyle(lineWidth: Stroke.thin, dash: [3, 4]))
                    if index == 0, active {
                        Circle()
                            .trim(from: 0, to: 0.3)
                            .stroke(IslandInk.text, style: StrokeStyle(lineWidth: Stroke.medium, lineCap: .round))
                            .rotationEffect(.degrees(turning ? 360 : 0))
                            .onAppear {
                                guard !reduceMotion else { return }
                                withAnimation(.linear(duration: MotionTime.panel * 4).repeatForever(autoreverses: false)) {
                                    turning = true
                                }
                            }
                    }
                }
                .frame(width: IslandInk.slotSide, height: IslandInk.slotSide)
            }
        }
        .accessibilityHidden(!active)
        .accessibilityLabel(Localized.string("island.job"))
    }
}
