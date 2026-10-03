import SwiftUI

/// A drawn slider's measures. The native Slider draws at the system's size
/// and tint, so it can never take Incredible's track and knob. A second look
/// (the first-run sound check) is another value of this type, not another view.
nonisolated package struct TrackSliderStyle: Sendable, Equatable {
    package let trackHeight: CGFloat
    /// Taller than the track so the pointer doesn't have to land on 6 px.
    package let hitHeight: CGFloat
    package let knob: CGFloat
    package let restScale: CGFloat
    package let activeScale: CGFloat
    package let fillHex: String
    /// White over the dark surface the slider sits on.
    package let trackAlpha: Double
    package let knobShadowAlpha: Double
    package let knobShadowRadius: CGFloat
    package let knobShadowY: CGFloat
    package let duration: Double
    package let curve: [Double]
    package let step: Double

    /// Incredible's island volume: firstRun-BOTAwJJ8.css, the .ov-volume-* rules.
    @MainActor package static let island = TrackSliderStyle(
        trackHeight: 6, hitHeight: 24, knob: 12, restScale: 0.75, activeScale: 1.15,
        fillHex: "4A9CFF", trackAlpha: 0.1,
        knobShadowAlpha: 0.4, knobShadowRadius: 1.5, knobShadowY: 1,
        duration: MotionTime.knob, curve: MotionCurve.standard, step: 0.05)

    package func knobScale(active: Bool) -> CGFloat {
        active ? activeScale : restScale
    }

    @MainActor package func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : MotionCurve.animation(curve, duration)
    }
}

/// The slider's arithmetic, apart from the view so it can be checked.
nonisolated package enum TrackSliderMath {
    package static func fraction(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// Where a point on the track lands, on the step grid like an HTML range input.
    package static func value(
        atX x: CGFloat, width: CGFloat, in range: ClosedRange<Double>, step: Double
    ) -> Double {
        guard width > 0 else { return range.lowerBound }
        let fraction = min(max(Double(x / width), 0), 1)
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        guard step > 0 else { return raw }
        return snapped(((raw - range.lowerBound) / step).rounded(), in: range, step: step)
    }

    /// One key press: off the grid it lands on the neighbouring step, not a step away from the odd value.
    package static func step(
        _ value: Double, by direction: Double, in range: ClosedRange<Double>, step: Double
    ) -> Double {
        guard step > 0 else { return min(max(value, range.lowerBound), range.upperBound) }
        // Floating division puts a grid value a hair under its index ((0.3 - 0.05) / 0.05 is
        // 4.999...); without the slack a key press would land back on the same step.
        let slack = 1e-9
        let index = (value - range.lowerBound) / step
        let target = direction > 0 ? (index + slack).rounded(.down) + 1 : (index - slack).rounded(.up) - 1
        return snapped(target, in: range, step: step)
    }

    /// The knob's leading edge: its centre sits on the edge of the fill, half
    /// past the track at either end, as Incredible's knob does.
    package static func knobX(fraction: Double, width: CGFloat, knob: CGFloat) -> CGFloat {
        width * fraction - knob / 2
    }

    /// A key or VoiceOver step is a whole edit, begun and ended, so a caller
    /// that saves on release saves it too; a press that changes nothing saves nothing.
    package static func commit(
        _ next: Double, over current: Double, set: (Double) -> Void, editing: (Bool) -> Void
    ) {
        guard next != current else { return }
        editing(true)
        set(next)
        editing(false)
    }

    private static func snapped(_ index: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        min(max(range.lowerBound + index * step, range.lowerBound), range.upperBound)
    }
}

/// Incredible's slider: a track, a fill up to the value and a knob that grows
/// under the pointer, on keyboard focus and while dragging. VoiceOver reads it
/// as an adjustable value, as it would the native Slider.
package struct TrackSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    let style: TrackSliderStyle
    let onEditingChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var hovering = false
    @State private var dragging = false

    package init(
        value: Binding<Double>, in range: ClosedRange<Double>, label: String,
        style: TrackSliderStyle = .island, onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.label = label
        self.style = style
        self.onEditingChanged = onEditingChanged
    }

    private var active: Bool { hovering || focused || dragging }

    package var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = TrackSliderMath.fraction(value, in: range)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Neutral.white.color.opacity(style.trackAlpha))
                    .frame(height: style.trackHeight)
                Capsule()
                    .fill(Swatch(style.fillHex).color)
                    .frame(width: width * fraction, height: style.trackHeight)
                Circle()
                    .fill(Neutral.white.color)
                    .shadow(color: Neutral.black.color.opacity(style.knobShadowAlpha),
                            radius: style.knobShadowRadius, y: style.knobShadowY)
                    .frame(width: style.knob, height: style.knob)
                    .scaleEffect(style.knobScale(active: active))
                    .offset(x: TrackSliderMath.knobX(fraction: fraction, width: width, knob: style.knob))
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(drag(width: width))
        }
        .frame(height: style.hitHeight)
        .onHover { hovering = $0 }
        .focusable()
        .focused($focused)
        // The grown knob is the focus mark, as in Incredible; a ring would draw it twice.
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .downArrow]) { _ in
            nudge(-1)
            return .handled
        }
        .onKeyPress(keys: [.rightArrow, .upArrow]) { _ in
            nudge(1)
            return .handled
        }
        .animation(style.animation(reduceMotion: reduceMotion), value: active)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(TrackSliderMath.fraction(value, in: 0...1)
            .formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !dragging {
                    dragging = true
                    onEditingChanged(true)
                }
                value = TrackSliderMath.value(atX: gesture.location.x, width: width, in: range, step: style.step)
            }
            .onEnded { _ in
                dragging = false
                onEditingChanged(false)
            }
    }

    private func nudge(_ direction: Double) {
        let next = TrackSliderMath.step(value, by: direction, in: range, step: style.step)
        TrackSliderMath.commit(next, over: value, set: { value = $0 }, editing: onEditingChanged)
    }
}
