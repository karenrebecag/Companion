import CompanionCore
import SwiftUI

/// P3: Incredible's voice line chip measures (referencia local).
enum VoiceLineChipMetrics {
    static let maxWidth: CGFloat = 480
    static let columnGap: CGFloat = 10
    /// Between sentences once hover lays them all out.
    static let lineGap: CGFloat = 6
    static let orb: CGFloat = IslandChrome.meterSide
    static let radius: CGFloat = Radius.panel
    static let textSize: CGFloat = TypeSize.heroBody
    static let lineHeight: CGFloat = 20
    /// From the island's top edge, centered under it.
    static let top: CGFloat = 40
    static let caret: CGFloat = 10
    static let caretRadius: CGFloat = 3
    static let caretTop: CGFloat = -4
    static let padding = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 16)
    static let pressedScale: CGFloat = 0.98
    static let rimWidth: CGFloat = 0.5
    static var rim: Color { Neutral.white.color.opacity(0.05) }
    // CSS blur is twice SwiftUI's shadow radius, so Incredible's 3 and 24 halve here.
    static var nearShadow: Color { Neutral.black.color.opacity(0.35) }
    static let nearRadius: CGFloat = 1.5
    static let nearY: CGFloat = 1
    static var farShadow: Color { Neutral.black.color.opacity(0.28) }
    static let farRadius: CGFloat = 12
    static let farY: CGFloat = 8
}

/// P3: how the chip and its sentences move, as Incredible's CSS does.
enum VoiceLineChipMotion {
    static let hiddenOffset: CGFloat = -4
    static let hiddenScale: CGFloat = 0.98
    static let hiddenBlur: CGFloat = 4
    /// Leaving: opacity and blur on 220 ms, the move on 260 ms, both standard.
    static let leave = IslandMotion.Curve.timing(MotionCurve.standard, 0.26)
    /// Entering bounces in.
    static let enter = IslandMotion.Curve.timing(MotionCurve.bounce, 0.36)
    /// The old sentence rolls up and out; the new one rolls in from below.
    static let lineOut = IslandMotion.Curve.timing(MotionCurve.standard, 0.26)
    static let lineIn = IslandMotion.Curve.timing(MotionCurve.bounce, 0.42)
    /// 150 % of a line, as a fraction.
    static let reelTravel: CGFloat = 1.5
    static let reelBlur: CGFloat = 2.5
}

/// Which part of the canvas the pointer is over.
enum IslandPointerTarget: Equatable {
    case island, voiceLine, outside
}

extension IslandChrome {
    /// The chip takes clicks but is not the island: hovering it must not open the
    /// island, which would take the turn away from the chip.
    static func pointerTarget(
        _ point: CGPoint, shape: CGRect, portal: CGRect?, answer: CGRect?, voiceLine: CGRect?
    ) -> IslandPointerTarget {
        if pointerInside(point, shape: shape, portal: portal, answer: answer) { return .island }
        if let voiceLine, pointerInside(point, rect: voiceLine) { return .voiceLine }
        return .outside
    }
}

/// P3: in passive, what the voice says rides here one sentence at a time; hover
/// shows them all and a click opens the island on the same turn.
struct VoiceLineChip: View {
    let line: VoiceLine
    let visible: Bool
    let startedAt: Date
    let speaking: Bool
    let levels: VoiceLevels
    let onEngage: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    /// How many words are said: none before the voice starts, so the chip opens on the
    /// first sentence instead of jumping back from the last; all once the turn is over.
    static func said(words: Int, settled: Bool, speaking: Bool, elapsed: Double) -> Int {
        if settled { return words }
        guard speaking else { return 0 }
        return IslandReveal.shown(words: words, elapsed: elapsed, speaking: true)
    }

    var body: some View {
        Button(action: onEngage) {
            HStack(alignment: .top, spacing: VoiceLineChipMetrics.columnGap) {
                Orb(state: .idle, levels: levels, accentColor: Semantic.accent)
                    .frame(width: VoiceLineChipMetrics.orb, height: VoiceLineChipMetrics.orb)
                TimelineView(.animation(paused: !speaking)) { context in
                    let said = Self.said(
                        words: line.words.count, settled: line.settled, speaking: speaking,
                        elapsed: context.date.timeIntervalSince(startedAt))
                    sentences(current: VoiceLine.current(line.lines, spoken: said))
                }
            }
            .padding(VoiceLineChipMetrics.padding)
            .background { plate }
            .frame(maxWidth: VoiceLineChipMetrics.maxWidth)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(VoiceLineChipPress())
        .onHover { expanded = $0 }
        .modifier(VoiceLineChipVeil(hidden: !visible, reduceMotion: reduceMotion))
        .animation(reduceMotion ? nil
            : (visible ? VoiceLineChipMotion.enter : VoiceLineChipMotion.leave).animation, value: visible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onEngage() }
    }

    @ViewBuilder
    private func sentences(current: Int) -> some View {
        if expanded {
            VStack(alignment: .leading, spacing: VoiceLineChipMetrics.lineGap) {
                ForEach(Array(line.lines.enumerated()), id: \.offset) { _, words in sentence(words) }
            }
        } else {
            ZStack(alignment: .topLeading) {
                sentence(line.lines.indices.contains(current) ? line.lines[current] : [])
                    .id(current)
                    .transition(reel)
            }
            .animation(reduceMotion ? nil : VoiceLineChipMotion.lineIn.animation, value: current)
            .clipped()
        }
    }

    private func sentence(_ words: [String]) -> some View {
        Text(words.joined(separator: " "))
            .font(Fonts.geist(VoiceLineChipMetrics.textSize))
            .foregroundStyle(IslandInk.text)
            .frame(minHeight: VoiceLineChipMetrics.lineHeight, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Under reduce motion Incredible hides the outgoing frame and moves nothing.
    private var reel: AnyTransition {
        guard !reduceMotion else { return .identity }
        let travel = VoiceLineChipMetrics.lineHeight * VoiceLineChipMotion.reelTravel
        return .asymmetric(
            insertion: .modifier(active: ReelFrame(offset: travel, blur: VoiceLineChipMotion.reelBlur, opacity: 0),
                                 identity: ReelFrame(offset: 0, blur: 0, opacity: 1))
                .animation(VoiceLineChipMotion.lineIn.animation),
            removal: .modifier(active: ReelFrame(offset: -travel, blur: VoiceLineChipMotion.reelBlur, opacity: 0),
                               identity: ReelFrame(offset: 0, blur: 0, opacity: 1))
                .animation(VoiceLineChipMotion.lineOut.animation))
    }

    private var plate: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: VoiceLineChipMetrics.caretRadius)
                .fill(IslandInk.panel)
                .frame(width: VoiceLineChipMetrics.caret, height: VoiceLineChipMetrics.caret)
                .rotationEffect(.degrees(45))
                .offset(y: VoiceLineChipMetrics.caretTop)
            RoundedRectangle(cornerRadius: VoiceLineChipMetrics.radius)
                .fill(IslandInk.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: VoiceLineChipMetrics.radius)
                        .strokeBorder(VoiceLineChipMetrics.rim, lineWidth: VoiceLineChipMetrics.rimWidth)
                }
        }
        .shadow(color: VoiceLineChipMetrics.nearShadow, radius: VoiceLineChipMetrics.nearRadius,
                y: VoiceLineChipMetrics.nearY)
        .shadow(color: VoiceLineChipMetrics.farShadow, radius: VoiceLineChipMetrics.farRadius,
                y: VoiceLineChipMetrics.farY)
    }
}

extension VoiceLineChip {
    /// Mounting starts from the hidden state, so the chip bounces in instead of popping
    /// (code review P3: the chip was inserted already lit).
    static func entering(reduceMotion: Bool) -> AnyTransition {
        .modifier(active: VoiceLineChipVeil(hidden: true, reduceMotion: reduceMotion),
                  identity: VoiceLineChipVeil(hidden: false, reduceMotion: reduceMotion))
    }
}

/// Incredible's hidden chip: transparent, a little up, a little small, blurred.
private struct VoiceLineChipVeil: ViewModifier {
    let hidden: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden && !reduceMotion ? VoiceLineChipMotion.hiddenOffset : 0)
            .scaleEffect(hidden && !reduceMotion ? VoiceLineChipMotion.hiddenScale : 1)
            .blur(radius: hidden && !reduceMotion ? VoiceLineChipMotion.hiddenBlur : 0)
    }
}

private struct ReelFrame: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(y: offset).blur(radius: blur).opacity(opacity)
    }
}

private struct VoiceLineChipPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? VoiceLineChipMetrics.pressedScale : 1)
    }
}
