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

    var body: some View {
        if contentHeight > maxHeight {
            ScrollView(.vertical) { measured }
                .defaultScrollAnchor(anchorBottom ? .bottom : nil)
                .scrollIndicators(.automatic)
                .frame(height: maxHeight, alignment: .top)
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
