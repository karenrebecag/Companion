import SwiftUI

// Arc's radio-cards (uiarc.dev, free registry: radio-cards.json), list
// layout: full-width cards, one ring that glides to the chosen card, one tab
// stop with arrows, Home and End. A SwiftUI reimplementation, not a port.

nonisolated package struct RadioCardOption<Value: Hashable>: Hashable {
    package let value: Value
    package let label: String
    package let description: String?
    package let meta: String?

    package init(value: Value, label: String, description: String? = nil, meta: String? = nil) {
        self.value = value
        self.label = label
        self.description = description
        self.meta = meta
    }

    /// What VoiceOver reads: the label, then whatever sets the card apart.
    package var accessibilityLabel: String {
        [label, description, meta]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

package enum RadioCardsMetrics {
    package static let padding: CGFloat = Space.x3_5
    package static let gap: CGFloat = Space.x2
    package static let radius: CGFloat = Radius.control
    package static let indicator: CGFloat = Space.x4
    /// The filled dot inside the indicator: leaves a visible gap to the outline.
    package static let dot: CGFloat = Space.x2
    package static let textGap: CGFloat = Space.x1
    package static let contentGap: CGFloat = Space.x3
    package static let ringWidth: CGFloat = Stroke.medium
    package static let duration = MotionTime.base
}

/// Which card is chosen, as a value, so the keyboard rules are testable.
nonisolated package struct RadioCardsSelection<Value: Hashable> {
    let options: [Value]
    package private(set) var selected: Value

    package init(options: [Value], selected: Value) {
        self.options = options
        self.selected = selected
    }

    package mutating func select(_ value: Value) {
        if options.contains(value) { selected = value }
    }

    /// One step along the list, wrapping at both ends; from a value that is
    /// not a card, down lands on the first and up on the last.
    @discardableResult
    package mutating func move(by step: Int) -> Value {
        guard !options.isEmpty else { return selected }
        guard let index = options.firstIndex(of: selected) else {
            selected = step < 0 ? options[options.count - 1] : options[0]
            return selected
        }
        let count = options.count
        selected = options[((index + step) % count + count) % count]
        return selected
    }

    @discardableResult
    package mutating func first() -> Value {
        if let head = options.first { selected = head }
        return selected
    }

    @discardableResult
    package mutating func last() -> Value {
        if let tail = options.last { selected = tail }
        return selected
    }
}

package struct RadioCards<Value: Hashable>: View {
    let label: String
    let options: [RadioCardOption<Value>]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ring

    package init(label: String, options: [RadioCardOption<Value>], selection: Binding<Value>) {
        self.label = label
        self.options = options
        self._selection = selection
    }

    package var body: some View {
        VStack(spacing: RadioCardsMetrics.gap) {
            ForEach(options, id: \.value) { option in
                card(option)
            }
        }
        .animation(Self.animation(reduceMotion: reduceMotion), value: selection)
        .accessibilityRepresentation {
            Picker(label, selection: $selection) {
                ForEach(options, id: \.value) { Text($0.accessibilityLabel).tag($0.value) }
            }
            .pickerStyle(.radioGroup)
        }
        // The list is the single tab stop; arrows move inside it.
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .up: move { $0.move(by: -1) }
            case .down: move { $0.move(by: 1) }
            default: break
            }
        }
        .onKeyPress(.home) { move { $0.first() }; return .handled }
        .onKeyPress(.end) { move { $0.last() }; return .handled }
    }

    /// The ring's one animation, nil under Reduce Motion so it jumps; the
    /// body uses this exact call, which is what the tests pin.
    static func animation(reduceMotion: Bool) -> Animation? {
        ChromeMotion.animation(
            MotionCurve.animation(MotionCurve.standard, RadioCardsMetrics.duration), reduceMotion: reduceMotion)
    }

    private func move(_ change: (inout RadioCardsSelection<Value>) -> Void) {
        var model = RadioCardsSelection(options: options.map(\.value), selected: selection)
        change(&model)
        selection = model.selected
    }

    private func card(_ option: RadioCardOption<Value>) -> some View {
        let on = option.value == selection
        return Button { selection = option.value } label: {
            HStack(alignment: .top, spacing: RadioCardsMetrics.contentGap) {
                indicator(on: on)
                VStack(alignment: .leading, spacing: RadioCardsMetrics.textGap) {
                    Text(option.label)
                        .font(Fonts.sans(TypeSize.caption).weight(.medium))
                        .foregroundStyle(Semantic.foreground)
                        .lineLimit(1)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .typeRole(.micro)
                            .foregroundStyle(Semantic.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let meta = option.meta, !meta.isEmpty {
                    Text(meta)
                        .font(Fonts.sans(TypeSize.micro))
                        .foregroundStyle(Semantic.mutedForeground)
                        .lineLimit(1)
                }
            }
            .padding(RadioCardsMetrics.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: RadioCardsMetrics.radius).fill(Semantic.surface))
            .overlay(RoundedRectangle(cornerRadius: RadioCardsMetrics.radius)
                .strokeBorder(Semantic.border, lineWidth: Stroke.hairline))
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: RadioCardsMetrics.radius)
                        .strokeBorder(Semantic.foreground, lineWidth: RadioCardsMetrics.ringWidth)
                        .matchedGeometryEffect(id: "ring", in: ring)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: RadioCardsMetrics.radius))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func indicator(on: Bool) -> some View {
        Circle()
            .strokeBorder(on ? Semantic.foreground : Semantic.borderStrong, lineWidth: Stroke.thin)
            .frame(width: RadioCardsMetrics.indicator, height: RadioCardsMetrics.indicator)
            .overlay {
                Circle()
                    .fill(Semantic.foreground)
                    .frame(width: RadioCardsMetrics.dot, height: RadioCardsMetrics.dot)
                    .scaleEffect(on ? 1 : 0)
            }
    }
}
