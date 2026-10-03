import SwiftUI

// Incredible's `.fr-dev-segment`: a small framed row of segments whose active
// one is a white chip with black text, moving at .22 s on the standard curve.

package enum SegmentedMetrics {
    package static let gap: CGFloat = Space.x0_5
    package static let padding: CGFloat = Space.x0_5
    package static let radius: CGFloat = Radius.chip
    /// The frame's radius less its padding, so the chip sits concentric.
    package static let segmentRadius: CGFloat = Radius.badge
    package static let minHeight: CGFloat = Space.x6
    package static let paddingX: CGFloat = Space.x3
    package static let duration = 0.22
}

package enum SegmentedLook {
    package static func background(selected: Bool) -> Color {
        selected ? Neutral.white.color : Color.clear
    }

    package static func foreground(selected: Bool) -> Color {
        selected ? Neutral.black.color : Semantic.mutedForeground
    }

    package static func weight(selected: Bool) -> Font.Weight {
        selected ? .semibold : .medium
    }
}

/// Which segment is on, as a value, so the keyboard rules are testable.
package struct SegmentedSelection<Value: Hashable> {
    let options: [Value]
    package private(set) var selected: Value

    package init(options: [Value], selected: Value) {
        self.options = options
        self.selected = selected
    }

    package mutating func select(_ value: Value) {
        if options.contains(value) { selected = value }
    }

    /// One step along the row, without wrapping; returns what is selected.
    @discardableResult
    package mutating func move(by step: Int) -> Value {
        if let index = options.firstIndex(of: selected) {
            selected = options[min(options.count - 1, max(0, index + step))]
        }
        return selected
    }
}

package struct SegmentedToggle<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var chip

    package init(options: [(Value, String)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    package var body: some View {
        HStack(spacing: SegmentedMetrics.gap) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index].0, options[index].1)
            }
        }
        .padding(SegmentedMetrics.padding)
        .background(RoundedRectangle(cornerRadius: SegmentedMetrics.radius).fill(Semantic.wash))
        .animation(reduceMotion ? nil : MotionCurve.animation(MotionCurve.standard, SegmentedMetrics.duration),
                   value: selection)
        .accessibilityElement(children: .contain)
        .focusable()
        .onMoveCommand { direction in
            var model = SegmentedSelection(options: options.map(\.0), selected: selection)
            switch direction {
            case .left: model.move(by: -1)
            case .right: model.move(by: 1)
            default: return
            }
            selection = model.selected
        }
    }

    private func segment(_ value: Value, _ title: String) -> some View {
        let on = value == selection
        return Button { selection = value } label: {
            Text(title)
                .font(Fonts.sans(TypeSize.caption).weight(SegmentedLook.weight(selected: on)))
                .foregroundStyle(SegmentedLook.foreground(selected: on))
                .lineLimit(1)
                .padding(.horizontal, SegmentedMetrics.paddingX)
                .frame(minHeight: SegmentedMetrics.minHeight)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: SegmentedMetrics.segmentRadius)
                            .fill(SegmentedLook.background(selected: true))
                            .matchedGeometryEffect(id: "chip", in: chip)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: SegmentedMetrics.segmentRadius))
        }
        .buttonStyle(.plain)
        // The row is the single tab stop; arrows move inside it.
        .focusable(false)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
