import CompanionCore
import CompanionUIPro
import SwiftUI

// Arc's voice-orb block on the island, built from CompanionUIPro's own
// pieces instead of island-made copies: the package VoiceOrb, the spoken
// words two lines tall under it, the end control in its own pill.

enum IslandVoiceStageMetrics {
    /// The orb's cloud needs room to read; at the lead column's 32 pt it is a dot.
    static let orb: CGFloat = 72
    static let endSide: CGFloat = 32
    static let pillPad: CGFloat = Space.x1
}

extension VoiceOrbState {
    init(island state: IslandOrbState) {
        switch state {
        case .idle: self = .idle
        case .listening: self = .listening
        case .thinking: self = .thinking
        case .speaking: self = .speaking
        }
    }
}

extension VoiceOrbPalette {
    /// The island is always dark: Arc's foreground body over the panel's
    /// black, accent and success in the cloud as Home's orb has them.
    static let island = VoiceOrbPalette(
        foreground: ArcTone.foreground.color,
        background: IslandInk.panel,
        tint: ArcTone.accent.color,
        tint2: ArcTone.success.color,
        isDark: true)
}

/// The package orb in the island's palette, fed the real meters.
struct IslandVoiceOrb: View {
    let state: IslandOrbState
    /// Nil lets the package run its own envelope: thinking has no meter.
    var levels: VoiceLevels?
    let size: CGFloat

    var body: some View {
        VoiceOrb(state: VoiceOrbState(island: state),
                 inputLevel: levels.map { Self.unit($0.mic) },
                 outputLevel: levels.map { Self.unit($0.agent) },
                 size: size, palette: .island,
                 accessibilityLabel: Localized.string("island.pebble"))
    }

    /// The package expects [0, 1]; a meter can hand back NaN on a dropped buffer.
    static func unit(_ level: Double) -> Double {
        level.isFinite ? min(max(level, 0), 1) : 0
    }
}

/// While it speaks: the orb centered, the words under it, the end control last.
struct IslandVoiceStage: View {
    let voice: VoiceViewModel
    let text: String
    let startedAt: Date
    let showsStop: Bool
    /// The spoken reply's own chart or table: it is in the same message, so it shows while the words are said.
    var visuals: (card: Card?, blocks: [AnswerBlock]) = (nil, [])
    let orbSpace: Namespace.ID
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: IslandGrid.groupGap) {
            IslandVoiceOrb(state: .speaking, levels: voice.levels, size: IslandVoiceStageMetrics.orb)
                .matchedGeometryEffect(id: IslandOrbTravel.id, in: orbSpace)
            IslandLiveReply(voice: voice, text: text, startedAt: startedAt, speaking: true, look: .transcript)
            if visuals.card != nil || !visuals.blocks.isEmpty {
                IslandInlineVisuals(card: visuals.card, blocks: visuals.blocks,
                                    width: IslandGrid.openColumn, room: IslandFit.tallRoom)
            }
            if showsStop {
                IslandVoiceControls(onStop: onStop)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Arc's voice controls: a raised pill with the end control on a 12 % danger wash.
struct IslandVoiceControls: View {
    let onStop: () -> Void

    var body: some View {
        Button(action: onStop) {
            Image(systemName: "stop.fill")
                .font(GeistFont.uiCaption)
                .foregroundStyle(IslandInk.stop)
                .frame(width: IslandVoiceStageMetrics.endSide, height: IslandVoiceStageMetrics.endSide)
                .background(Circle().fill(ArcTone.wash(ArcTone.danger)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .islandTooltip(Localized.string("island.tip.stop"))
        .accessibilityLabel(Localized.string("island.tip.stop"))
        .padding(IslandVoiceStageMetrics.pillPad)
        .background(Capsule().fill(ArcTone.surfaceRaised.color))
        .overlay(Capsule().strokeBorder(ArcTone.border.color, lineWidth: Stroke.hairline))
    }
}

/// The package loader in the island's tones and words.
struct IslandLoader: View {
    let status: MorphLoaderStatus
    let size: CGFloat

    var body: some View {
        CompanionUIPro::MorphLoader(
            variant: .ring, status: Self.package(status), size: size,
            successColor: ArcTone.success.color, errorColor: ArcTone.danger.color,
            label: Localized.string("loader.loading"),
            successLabel: Localized.string("loader.success"),
            errorLabel: Localized.string("loader.error"))
    }

    static func package(_ status: MorphLoaderStatus) -> CompanionUIPro::MorphLoaderStatus {
        switch status {
        case .loading: .loading
        case .success: .success
        case .error: .error
        }
    }
}
