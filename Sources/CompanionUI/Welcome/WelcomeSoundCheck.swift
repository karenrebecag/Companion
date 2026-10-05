import CompanionCore
import SwiftUI

extension TrackSliderStyle {
    /// Incredible's sound check slider: styles-CTdsYdwA.css @4480-5211, the
    /// .fr-sound-slider rules (a 28 px input, a 4 px track and an 18 px thumb).
    @MainActor static let soundCheck = TrackSliderStyle(
        trackHeight: 4, hitHeight: 28, knob: 18, restScale: 1, activeScale: 1.12,
        fillHex: "FFFFFF", trackAlpha: 0.22,
        knobShadowAlpha: 0.25, knobShadowRadius: 6, knobShadowY: 4,
        duration: MotionTime.base, curve: MotionCurve.easeOut, step: 0.01)
}

/// Incredible's sound check card (WIN-8), on the dark the hello screen dims
/// to while it is up: Incredible draws it over its dusk, and the white
/// slider is only legible there. styles-CTdsYdwA.css @3301-5984.
struct WelcomeSoundCheck: View {
    var welcome: WelcomeModel
    let volume: OutputVolume

    private static let width: CGFloat = 440
    private static let leadWidth: CGFloat = 360
    private static let lead = Neutral.white.color.opacity(0.72)

    private var leadKey: String { volume.muted ? "welcome.sound.muted" : "welcome.sound.body" }

    var body: some View {
        VStack(spacing: Space.x4) {
            Text(Localized.string("welcome.sound.title"))
                .font(Fonts.geist(TypeSize.pageTitle))
                .fontWeight(.semibold)
                .tracking(Tracking.title, at: TypeSize.pageTitle)
                .foregroundStyle(Neutral.white.color)
                .accessibilityAddTraits(.isHeader)
            Text(Localized.string(leadKey))
                .font(Fonts.geist(TypeSize.rowTitle))
                .foregroundStyle(Self.lead)
                .frame(maxWidth: Self.leadWidth)
            slider
                .padding(.top, Space.x2)
            actions
                .padding(.top, Space.x4)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: Self.width)
    }

    private var slider: some View {
        HStack(spacing: Space.x3) {
            Image(systemName: "speaker.wave.1.fill").accessibilityHidden(true)
            TrackSlider(
                value: Binding(get: { volume.level }, set: { welcome.setVolume($0) }),
                in: 0...1, label: Localized.string("welcome.sound.slider"), style: .soundCheck,
                onEditingChanged: { editing in
                    if !editing { Task { await welcome.probe() } }
                })
                // Muted, the slider could not make anything heard: Incredible
                // disables its input at half opacity when it can't act.
                .disabled(volume.muted)
                .opacity(volume.muted ? 0.5 : 1)
                .accessibilityHint(volume.muted ? Localized.string("welcome.sound.muted") : "")
            Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
        }
        .font(Fonts.geist(TypeSize.rowTitle))
        .foregroundStyle(Self.lead)
    }

    private var actions: some View {
        VStack(spacing: Space.x2) {
            Button(Localized.string("welcome.sound.heard")) { welcome.confirmSound() }
                .buttonStyle(SoundCheckButtonStyle(primary: true))
            Button(Localized.string("welcome.sound.anyway")) { welcome.confirmSound() }
                .buttonStyle(SoundCheckButtonStyle(primary: false))
        }
    }
}

/// .fr-sound-btn--primary (a white pill) and --quiet (muted text).
private struct SoundCheckButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        SoundCheckButtonFace(label: configuration.label, pressed: configuration.isPressed, primary: primary)
    }
}

private struct SoundCheckButtonFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    let primary: Bool
    /// The pill's 22 px side padding, between two spacing steps.
    private static var primaryInset: CGFloat { 22 }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        label
            .font(Fonts.geist(TypeSize.body))
            .fontWeight(primary ? .semibold : .medium)
            .padding(.horizontal, primary ? Self.primaryInset : Space.x3)
            .padding(.vertical, primary ? Space.x3 : Space.x2)
            .foregroundStyle(primary ? Neutral.black.color : Neutral.white.color.opacity(hovering ? 1 : 0.6))
            .background {
                if primary {
                    Capsule().fill(Neutral.white.color.opacity(hovering ? 0.9 : 1))
                }
            }
            .contentShape(Capsule())
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : MotionCurve.animation(MotionCurve.standard, MotionTime.fast), value: hovering)
            .animation(reduceMotion ? nil : MotionCurve.animation(MotionCurve.easeOut, MotionTime.base), value: pressed)
            .onHover { hovering = $0 }
    }
}
