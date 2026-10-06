import SwiftUI

/// The island's column: it hugs short content and scrolls vertically only
/// past its cap, as Incredible's does. A greedy ScrollView would make every
/// island cap-tall, and the island measures its content with `fixedSize`,
/// where a ScrollView without an explicit height reports no useful size.
struct IslandColumn<Content: View>: View {
    let maxHeight: CGFloat
    /// A growing list keeps its newest end in view when it scrolls.
    var anchorBottom = false
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        if contentHeight > maxHeight {
            let edges = IslandColumnFade.edges(offset: offset, content: contentHeight, viewport: maxHeight)
            ScrollView(.vertical) { measured }
                .defaultScrollAnchor(anchorBottom ? .bottom : nil)
                .scrollIndicators(.automatic)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in offset = y }
                .frame(height: maxHeight, alignment: .top)
                // Arc's scroll-area: an edge fades only where there is more to read.
                .mask(IslandColumnFade.mask(top: edges.top, bottom: edges.bottom, height: maxHeight))
        } else {
            // `frame(maxHeight:)` would take the offered height up to the cap;
            // this keeps the content's own height. On the unmeasured first
            // frame it also stops an over-tall column at the cap.
            CappedHeight(maxHeight: maxHeight) { measured }
                .clipped()
        }
    }

    private var measured: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
    }
}

private struct CappedHeight: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: natural.width, height: min(natural.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

enum IslandColumnFade {
    static let length: CGFloat = Space.x6

    static func edges(offset: CGFloat, content: CGFloat, viewport: CGFloat) -> (top: Bool, bottom: Bool) {
        guard content > viewport else { return (false, false) }
        return (offset > 0.5, offset < content - viewport - 0.5)
    }

    static func mask(top: Bool, bottom: Bool, height: CGFloat) -> LinearGradient {
        let share = height > 0 ? min(0.5, length / height) : 0
        return LinearGradient(stops: [
            .init(color: top ? .clear : .black, location: 0),
            .init(color: .black, location: share),
            .init(color: .black, location: 1 - share),
            .init(color: bottom ? .clear : .black, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}
