import CompanionCore
import SwiftUI

// Wave 16o-1: the island clips its content to the notch shape, so a tooltip
// or a dropdown drawn inside it is cut at the shape's edge or hidden under the
// camera. Triggers publish their bounds instead, and one layer above the clip
// draws them anywhere in the canvas, as Incredible's DOM portal does.

public enum PortalSide: Equatable, Sendable { case above, below }
public enum PortalAlign: Equatable, Sendable { case center, leading }

public enum PortalPlacement {
    /// Incredible: tooltips 4 px above their trigger, 6 px when below.
    public static let gapAbove: CGFloat = Space.x1
    public static let gapBelow: CGFloat = Space.x1_5
    /// Nothing is drawn closer than this to the canvas edge.
    public static let edgeInset: CGFloat = Space.x2

    /// Canvas coordinates, origin top-left. `forbidden` is the notch band:
    /// whatever lands there sits under the camera housing.
    public static func place(
        anchor: CGRect, size: CGSize, canvas: CGSize, forbidden: CGRect?,
        prefers: PortalSide = .above, align: PortalAlign = .center
    ) -> (origin: CGPoint, side: PortalSide) {
        let rawX = align == .center ? anchor.midX - size.width / 2 : anchor.minX
        let x = min(max(rawX, edgeInset), canvas.width - edgeInset - size.width)
        let aboveY = anchor.minY - gapAbove - size.height
        let belowY = anchor.maxY + gapBelow
        func fits(_ y: CGFloat) -> Bool {
            let rect = CGRect(origin: CGPoint(x: x, y: y), size: size)
            let inside = y >= 0 && rect.maxY <= canvas.height
            return inside && !(forbidden.map { $0.intersects(rect) } ?? false)
        }
        let order: [PortalSide] = prefers == .above ? [.above, .below] : [.below, .above]
        let side = order.first { fits($0 == .above ? aboveY : belowY) } ?? order[0]
        return (CGPoint(x: x, y: side == .above ? aboveY : belowY), side)
    }
}

/// Who owns the click area: a popover leaving (its removal transition ends
/// after the next one opened) must not erase or move the newcomer's frame.
public enum PortalFrame {
    public static func next(
        current: CGRect?, report: CGRect?, from kind: IslandPopoverKind, active: IslandPopoverKind?
    ) -> CGRect? {
        if kind == active { return report }
        return active == nil ? nil : current
    }
}

/// What a trigger asks the portal to draw.
enum PortalRequest {
    case tooltip(String)
    case popover(IslandPopoverKind)

    var id: String {
        switch self {
        case .tooltip(let text): "tooltip:" + text
        case .popover(let kind): "popover:\(kind)"
        }
    }
}

struct PortalItem {
    let request: PortalRequest
    let anchor: Anchor<CGRect>
}

struct IslandPortalKey: PreferenceKey {
    static let defaultValue: [PortalItem] = []
    static func reduce(value: inout [PortalItem], nextValue: () -> [PortalItem]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func portal(_ request: PortalRequest?) -> some View {
        anchorPreference(key: IslandPortalKey.self, value: .bounds) { anchor in
            request.map { [PortalItem(request: $0, anchor: anchor)] } ?? []
        }
    }
}

/// Measures its content, then places it with `PortalPlacement`. Hidden until
/// measured, so it never flashes at the canvas origin.
struct PortalPlaced<Content: View>: View {
    let anchor: CGRect
    let canvas: CGSize
    let forbidden: CGRect
    var prefers: PortalSide = .above
    var align: PortalAlign = .center
    /// Told the placed frame, for the click area.
    var onFrame: (CGRect?) -> Void = { _ in }
    @ViewBuilder let content: () -> Content
    @State private var size: CGSize = .zero

    var body: some View {
        let placed = PortalPlacement.place(anchor: anchor, size: size, canvas: canvas,
                                           forbidden: forbidden, prefers: prefers, align: align)
        content()
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .opacity(size == .zero ? 0 : 1)
            .offset(x: placed.origin.x, y: placed.origin.y)
            .onChange(of: CGRect(origin: placed.origin, size: size), initial: true) { _, rect in
                onFrame(size == .zero ? nil : rect)
            }
            .onDisappear { onFrame(nil) }
    }
}

/// Incredible's tooltip: a near-black pill, 14 medium, opacity only.
struct IslandTooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Fonts.geist(TypeSize.rowTitle).weight(.medium))
            .foregroundStyle(IslandInk.text)
            .padding(.horizontal, Space.x2)
            .padding(.vertical, Space.x1)
            .background(Capsule().fill(IslandInk.tooltip))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
