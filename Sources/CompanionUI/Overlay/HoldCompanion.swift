import CompanionCore
import SwiftUI

/// The pill that rides the cursor while the key is held: the orb, what just flashed on
/// it, and what the user handed over stacked above. Laid out from its top-left corner,
/// which `PointerOrb` keeps trailing the cursor.
struct HoldCompanion: View {
    let state: HoldCompanionState
    let listening: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// While held, through the linger, and until the fade out has played.
    static func mounts(listening: Bool, mounted: Bool) -> Bool {
        listening || mounted
    }

    var body: some View {
        let animates = HoldCompanionMotion.animates(reduceMotion: reduceMotion)
        HoldCompanionPill(state: state, listening: listening, animates: animates)
            .overlay(alignment: .bottomLeading) {
                HoldCompanionStack(state: state, animates: animates)
                    .offset(x: HoldCompanionMetrics.pillInset,
                            y: HoldCompanionMetrics.pillHeight - HoldCompanionMetrics.stackLift)
            }
            .opacity(state.visible ? 1 : 0)
            .scaleEffect(state.visible ? 1 : HoldCompanionMotion.appearScale, anchor: .center)
            .animation(HoldCompanionMotion.appear.animation, value: state.visible)
            .fixedSize()
    }
}

private struct HoldCompanionPill: View {
    let state: HoldCompanionState
    let listening: Bool
    let animates: Bool
    /// The face keeps its last glyph while it fades, as Incredible's does.
    @State private var shownFlash: HoldItem?
    @State private var gulps = 0

    var body: some View {
        let gulping = HoldStack.gulping(state.stack, nowMs: state.clockMs)
        ZStack {
            Orb(state: listening ? .listening : .idle, levels: VoiceLevels(mic: 0, agent: 0),
                accentColor: Semantic.accent)
            face
        }
        .frame(width: HoldCompanionMetrics.orb, height: HoldCompanionMetrics.orb)
        .clipShape(Circle())
        .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: animates ? state.flashSeq : 0) {
            $0.scaleEffect($1)
        } keyframes: { _ in
            HoldCompanionKeyframes.land
        }
        .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: animates ? gulps : 0) {
            $0.scaleEffect($1)
        } keyframes: { _ in
            HoldCompanionKeyframes.gulp
        }
        .padding(.horizontal, HoldCompanionMetrics.pillInset)
        .frame(height: HoldCompanionMetrics.pillHeight)
        .onChange(of: state.flash) { _, flash in
            if let flash { shownFlash = flash }
        }
        .onChange(of: gulping) { _, now in
            if now { gulps += 1 }
        }
    }

    private var face: some View {
        let on = state.flash != nil
        return ZStack {
            Circle().fill(HoldCompanionMetrics.face.color)
            if let shownFlash {
                HoldGlyph(item: shownFlash, side: HoldCompanionMetrics.glyph)
                    .id(state.flashSeq)
                    .transition(animates ? .holdGlyph : .identity)
            }
        }
        .opacity(on ? 1 : 0)
        .animation((on ? HoldCompanionMotion.flashOn : HoldCompanionMotion.flashOff).animation, value: on)
        .animation(animates ? HoldCompanionMotion.glyphIn.animation : nil, value: state.flashSeq)
    }
}

private struct HoldCompanionStack: View {
    let state: HoldCompanionState
    let animates: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(Array(state.stack.enumerated()), id: \.element.item.id) { index, entry in
                HoldChip(item: entry.item, leaving: HoldStack.leaving(entry, nowMs: state.clockMs),
                         animates: animates)
                    .offset(y: -CGFloat(index) * HoldCompanionMotion.slotStep)
                    .animation(animates ? HoldCompanionMotion.slotMove.animation : nil, value: index)
            }
        }
    }
}

/// One handed-over item: it springs out of the orb and falls back into it when it leaves.
struct HoldChip: View {
    let item: HoldItem
    let leaving: Bool
    let animates: Bool
    @State private var arrived = false

    var body: some View {
        let out = leaving || !arrived
        HStack(spacing: HoldCompanionMetrics.chipGap) {
            HoldGlyph(item: item, side: HoldCompanionMetrics.chipIcon)
                .opacity(HoldCompanionMetrics.iconOpacity)
            HoldCappedWidth(limit: HoldCompanionMetrics.chipTextMax) {
                Text(item.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(Fonts.geist(TypeSize.body).weight(.medium))
        .foregroundStyle(Neutral.white.color)
        .padding(.leading, HoldCompanionMetrics.chipLead)
        .padding(.trailing, HoldCompanionMetrics.chipTrail)
        .frame(height: HoldCompanionMetrics.chipHeight)
        .fixedSize()
        .background(Capsule().fill(HoldCompanionMetrics.face.color))
        .shadow(color: Neutral.black.color.opacity(HoldCompanionMetrics.shadowOpacity),
                radius: HoldCompanionMetrics.shadowRadius, y: HoldCompanionMetrics.shadowY)
        .visualEffect { content, proxy in
            // It grows from a point under its own left edge: where the orb is.
            content.scaleEffect(out ? HoldCompanionMotion.chipScale : 1, anchor: HoldChip.anchor(proxy.size))
        }
        .offset(y: out ? HoldCompanionMotion.chipDrop : 0)
        .opacity(out ? 0 : 1)
        .animation(animates ? (leaving ? HoldCompanionMotion.chipOut : HoldCompanionMotion.chipIn).animation : nil,
                   value: out)
        .onAppear { arrived = true }
    }

    nonisolated static func anchor(_ size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .bottomLeading }
        return UnitPoint(x: HoldCompanionMetrics.chipOrigin.x / size.width,
                         y: (size.height + HoldCompanionMetrics.chipOrigin.y) / size.height)
    }
}

/// Offers its content at most `limit` wide whatever it is offered, even an ideal size,
/// so a long label truncates instead of running past the chip.
struct HoldCappedWidth: Layout {
    let limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = min(proposal.width ?? limit, limit)
        return content.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// The kind of thing touched, or the app it happened in.
struct HoldGlyph: View {
    let item: HoldItem
    let side: CGFloat

    var body: some View {
        Image(systemName: Self.symbol(item.kind))
            .resizable()
            .scaledToFit()
            .fontWeight(.bold)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }

    static func symbol(_ kind: HoldItem.Kind) -> String {
        switch kind {
        case .file: "doc"
        case .selectedText: "text.cursor"
        case .copied: "doc.on.clipboard"
        case .window, .dialog: "macwindow"
        case .tab: "globe"
        case .button: "cursorarrow.click"
        case .cell: "tablecells"
        case .typed: "keyboard"
        }
    }
}

extension AnyTransition {
    /// The glyph rolls up through the orb's face: in from below, out above, blurred on the way.
    static var holdGlyph: AnyTransition {
        let travel = HoldCompanionMetrics.glyph * HoldCompanionMotion.glyphTravel
        let blur = HoldCompanionMotion.glyphBlur
        return .asymmetric(
            insertion: .modifier(active: IslandMoveModifier(opacity: 0, blur: blur, offset: travel),
                                 identity: IslandMoveModifier(opacity: 1, blur: 0, offset: 0))
                .animation(HoldCompanionMotion.glyphIn.animation),
            removal: .modifier(active: IslandMoveModifier(opacity: 0, blur: blur, offset: -travel),
                               identity: IslandMoveModifier(opacity: 1, blur: 0, offset: 0))
                .animation(HoldCompanionMotion.glyphOut.animation))
    }
}
