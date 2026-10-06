import SwiftUI

// Wave 16l-2: Incredible's switch, select and menu, measured in its CSS.
// The native Toggle and Picker draw at the system's size and colours, so
// they can never match; these are drawn.

package struct SwitchGeometry: Sendable, Equatable {
    package let width: CGFloat
    package let height: CGFloat
    package let thumb: CGFloat
    package let pad: CGFloat

    package static let medium = SwitchGeometry(
        width: ControlMetrics.switchWidth, height: ControlMetrics.switchHeight,
        thumb: ControlMetrics.switchThumb, pad: ControlMetrics.switchPad)
    package static let small = SwitchGeometry(
        width: ControlMetrics.switchSmallWidth, height: ControlMetrics.switchSmallHeight,
        thumb: ControlMetrics.switchSmallThumb, pad: ControlMetrics.switchPad)

    /// How far the thumb moves between off and on.
    package var travel: CGFloat { width - thumb - pad * 2 }

    package static let offTrackAlpha = 0.16
    package static let duration = 0.22
}

package enum SelectMetrics {
    package static let height: CGFloat = 42
    package static let smallHeight: CGFloat = ControlMetrics.selectSmallHeight
    package static let paddingX: CGFloat = Space.x3
    package static let gap: CGFloat = Space.x2
    package static let radius: CGFloat = Radius.control
}

package enum MenuMetrics {
    package static let padding: CGFloat = Space.x1_5
    package static let gap: CGFloat = Space.x0_5
    package static let radius: CGFloat = Radius.cardSm
    package static let itemPaddingY: CGFloat = Space.x2
    package static let itemPaddingX: CGFloat = Space.x2_5
    package static let itemRadius: CGFloat = Radius.badge
    package static let itemGap: CGFloat = Space.x2_5
    package static let islandWidth: CGFloat = 230
    package static let enterScale: CGFloat = 0.97
    package static let duration = MotionTime.base
}

/// Incredible's switch: black track when on, 16 % black when off, a white
/// thumb; on dark surfaces a 12 % white track that turns green.
package struct IncredibleSwitch: View {
    let label: String
    @Binding var isOn: Bool
    var geometry: SwitchGeometry = .medium
    var enabled = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package init(_ label: String, isOn: Binding<Bool>,
                geometry: SwitchGeometry = .medium, enabled: Bool = true) {
        self.label = label
        self._isOn = isOn
        self.geometry = geometry
        self.enabled = enabled
    }

    package var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Circle()
                    .fill(Neutral.white.color)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                    .frame(width: geometry.thumb, height: geometry.thumb)
                    .padding(geometry.pad)
                    .offset(x: isOn ? geometry.travel : 0)
            }
            .frame(width: geometry.width, height: geometry.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : StateAlpha.disabled)
        .animation(reduceMotion ? nil
                   : MotionCurve.animation(MotionCurve.settle, SwitchGeometry.duration),
                   value: isOn)
        // VoiceOver reads a real switch: label, state and toggle action. It
        // acts on the representation, so the disabled guard lives in its
        // binding too, or a greyed-out switch still flips (review 16l).
        .accessibilityRepresentation {
            Toggle(label, isOn: Binding(
                get: { isOn },
                set: { isOn = Self.write($0, over: isOn, enabled: enabled) }))
            .disabled(!enabled)
        }
    }

    /// What a write from assistive technology leaves behind.
    package static func write(_ value: Bool, over current: Bool, enabled: Bool) -> Bool {
        enabled ? value : current
    }

    private var track: Color {
        if scheme == .dark {
            return isOn ? Palette.signalGreen.color.opacity(0.9) : Neutral.white.color.opacity(0.12)
        }
        return isOn ? Semantic.foreground : Neutral.black.color.opacity(SwitchGeometry.offTrackAlpha)
    }
}
