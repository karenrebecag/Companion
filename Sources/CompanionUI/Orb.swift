import CompanionCore
import SwiftUI

public struct Orb: View {
    let state: TurnState
    let levels: VoiceLevels
    let accentColor: Color

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public init(
        state: TurnState,
        levels: VoiceLevels,
        accentColor: Color
    ) {
        self.state = state
        self.levels = levels
        self.accentColor = accentColor
    }

    public var body: some View {
        let live: Double = {
            switch state {
            case .listening: levels.mic
            case .speaking: levels.agent
            default: 0
            }
        }()
        ZStack {
            OrbView(
                configuration: OrbAppearance.configuration(
                    for: state,
                    accent: accentColor,
                    reduceMotion: reduceMotion)
            )
            .padding(Space.x2)
            .scaleEffect(
                reduceMotion ? 1 : OrbAppearance.scaleFromLevel(live))
            .animation(.easeOut(duration: 0.08), value: levels)
            .animation(
                reduceMotion
                    ? .easeOut(duration: MotionTime.fast)
                    : .springSelect,
                value: state)
            .opacity(OrbAppearance.opacity(for: state))
            ShimmerRing(
                active: state == .listening || state == .thinking,
                thinking: state == .thinking,
                reduceMotion: reduceMotion)
        }
    }
}

/// Press feedback lives on the control that owns the orb, so Orb's
/// (state, levels, accentColor) contract stays put.
struct OrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(OrbAppearance.pressScale(configuration.isPressed))
            .animation(.springPress, value: configuration.isPressed)
    }
}
