import SwiftUI

// The chrome every result document shares: the dark card with its corner
// glow, the scroll that keeps the title inside it, the close button that
// shows on hover, and the chips (sources, actions). The island's shape is
// black; the card sits on it a shade lighter so the document reads as paper.

struct IslandDocFrame<Content: View>: View {
    let accent: Swatch
    let maxHeight: CGFloat
    var onDismiss: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var entered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DocCardMetrics.radius, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            IslandColumn(maxHeight: maxHeight) {
                content()
                    .padding(.horizontal, DocCardMetrics.padX)
                    .padding(.top, DocCardMetrics.padTop)
                    .padding(.bottom, DocCardMetrics.padBottom)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let onDismiss {
                DocToolButton(action: onDismiss)
                    .padding(DocCardMetrics.toolInset)
                    .opacity(hovering ? 1 : 0)
                    .animation(reduceMotion ? nil : MotionCurve.animation(MotionCurve.settle, MotionTime.fast),
                               value: hovering)
            }
        }
        .frame(maxWidth: .infinity)
        .background { chrome }
        .clipShape(shape)
        .shadow(color: .black.opacity(DocCardInk.shadowTight), radius: DocCardMetrics.shadowTight,
                y: DocCardMetrics.shadowTight)
        .shadow(color: .black.opacity(DocCardInk.shadowDrop), radius: DocCardMetrics.shadowBlur,
                y: DocCardMetrics.shadowDrop)
        .opacity(entered || reduceMotion ? 1 : 0)
        .offset(y: entered || reduceMotion ? 0 : DocCardMotion.enterLift)
        .scaleEffect(entered || reduceMotion ? 1 : DocCardMotion.enterScale, anchor: .top)
        .onHover { hovering = $0 }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(MotionCurve.animation(MotionCurve.settle, DocCardMotion.enter)) { entered = true }
        }
        .accessibilityElement(children: .contain)
    }

    private var chrome: some View {
        ZStack {
            DocCardInk.surface.color
            RadialGradient(
                stops: [
                    .init(color: accent.color.opacity(DocCardMetrics.glowStrong), location: 0),
                    .init(color: accent.color.opacity(DocCardMetrics.glowSoft), location: DocCardMetrics.glowMidStop),
                    .init(color: .clear, location: DocCardMetrics.glowEndStop),
                ],
                center: .topTrailing, startRadius: 0, endRadius: DocCardMetrics.glowRadius)
        }
        .clipShape(shape)
    }
}

/// Each block of the document fades in a beat after the one before it.
struct DocFadeIn: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(MotionCurve.animation(MotionCurve.standard, DocCardMotion.fade)
                    .delay(DocCardMotion.delay(at: index))) { shown = true }
            }
    }
}

struct DocToolButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Fonts.geist(TypeSize.micro).weight(.semibold))
                .foregroundStyle(Color.white.opacity(hovering ? 1 : DocCardInk.chipText))
                .frame(width: DocCardMetrics.toolSide, height: DocCardMetrics.toolSide)
                .background(Circle().fill((hovering ? DocCardInk.toolFillHover : DocCardInk.toolFill).color))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .accessibilityLabel(Localized.string("island.result.dismiss"))
    }
}

/// An outlined pill that fills white under the pointer: the sources use the
/// larger measure, the actions the smaller one.
struct DocChip<Label: View>: View {
    enum Scale { case source, action }
    let scale: Scale
    var action: (() -> Void)?
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    private var height: CGFloat { scale == .source ? DocCardMetrics.sourceHeight : DocCardMetrics.chipHeight }
    private var padX: CGFloat { scale == .source ? DocCardMetrics.sourcePadX : DocCardMetrics.chipPadX }
    private var ring: Double { scale == .source ? DocCardInk.sourceRing : DocCardInk.chipRing }
    private var ink: Double { scale == .source ? DocCardInk.sourceText : DocCardInk.chipText }
    private var inverted: Bool { hovering && action != nil }

    var body: some View {
        let pill = label()
            .font(Fonts.geist(scale == .source ? DocCardMetrics.sourceSize : DocCardMetrics.chipSize)
                .weight(scale == .source ? .medium : .semibold))
            .foregroundStyle(inverted ? DocCardInk.surface.color : Color.white.opacity(ink))
            .lineLimit(1)
            .padding(.horizontal, padX)
            .frame(height: height)
            .background(Capsule().fill(inverted ? Color.white : .clear))
            .overlay(Capsule().strokeBorder(Color.white.opacity(inverted ? 1 : ring), lineWidth: Stroke.hairline))
            .contentShape(Capsule())
            .animation(MotionCurve.animation(MotionCurve.settle, MotionTime.base), value: inverted)
        if let action {
            Button(action: action) { pill }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { hovering = $0 }
        } else {
            pill
        }
    }
}

/// The sources under the prose: one chip per link, opening only what has an address.
struct DocSources: View {
    let links: IslandResultCardModel.Links
    let onOpen: (URL) -> Void

    var body: some View {
        if !links.chips.isEmpty {
            WrappingRow(spacing: DocCardMetrics.chipGap) {
                ForEach(links.chips) { chip in
                    DocChip(scale: .source, action: links.urls[chip.id].map { url in { onOpen(url) } }) {
                        HStack(spacing: DocCardMetrics.chipGap / 2) {
                            Image(systemName: chip.kind == .app ? "app" : "doc")
                                .font(Fonts.geist(DocCardMetrics.sourceIcon))
                            Text(chip.label).truncationMode(.middle)
                        }
                    }
                    .accessibilityHint(links.urls[chip.id]?.absoluteString ?? "")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DocCardMetrics.sourcesTopPad)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(DocCardInk.sourcesLine)).frame(height: Stroke.hairline)
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// A column that spends no spacing on a child with no height: a slot the host
/// leaves empty (no visuals, no choice) must not widen the gap around it.
struct DocColumn: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        let shown = sizes.filter { $0.height > 0 }
        let height = shown.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, shown.count - 1))
        return CGSize(width: proposal.width ?? (sizes.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: size.height))
            if size.height > 0 { y += size.height + spacing }
        }
    }
}

extension View {
    /// SwiftUI adds `lineSpacing` between lines only; CSS gives every line
    /// the whole box. Half the extra goes above and below, so one line and
    /// ten lines both measure what the reference does.
    func docLineBox(size: CGFloat, leading: CGFloat) -> some View {
        let extra = DocCardMetrics.lineExtra(size: size, leading: leading)
        return lineSpacing(extra).padding(.vertical, extra / 2)
    }
}
