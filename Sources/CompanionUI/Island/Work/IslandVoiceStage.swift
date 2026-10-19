import CompanionCore
import CompanionUIPro
import SwiftUI

// Arc's voice block on the island: a static mark where the package orb was
// (Karen chose performance over the animated sphere, 2026-10-13), the spoken
// words two lines tall under it, the end control in its own pill.

enum IslandVoiceStageMetrics {
    /// Keeps the slot the orb had, so the speaking island holds its height.
    static let mark: CGFloat = 72
    static let glyph: CGFloat = 28
    static let endSide: CGFloat = 32
    static let pillPad: CGFloat = Space.x1
}

/// While it speaks: the mark centered, the words under it, the end control last.
struct IslandVoiceStage: View {
    let voice: VoiceViewModel
    let text: String
    let startedAt: Date
    let showsStop: Bool
    /// The spoken reply's own chart or table: it is in the same message, so it shows while the words are said.
    var visuals: IslandView.InlineVisuals = ([], [])
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: IslandGrid.groupGap) {
            Image(systemName: "waveform")
                .font(Fonts.symbol(IslandVoiceStageMetrics.glyph, weight: .medium))
                .foregroundStyle(IslandInk.text)
                .frame(width: IslandVoiceStageMetrics.mark, height: IslandVoiceStageMetrics.mark)
                .accessibilityHidden(true)
            if !text.isEmpty {
                IslandReply(text: text, startedAt: startedAt, speaking: true, look: .transcript)
            }
            if !visuals.cards.isEmpty || !visuals.blocks.isEmpty {
                IslandInlineVisuals(cards: visuals.cards, blocks: visuals.blocks,
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
