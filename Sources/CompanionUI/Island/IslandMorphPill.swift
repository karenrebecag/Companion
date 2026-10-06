import SwiftUI

/// Arc's confirm-morph face on the island: one raised pill that holds the
/// question (or what was done) and its answers, so a confirmation never
/// grows into a card.
enum IslandMorphMetrics {
    static let height: CGFloat = 32
    /// The answers sit 4 inside the pill: concentric pills.
    static let inset: CGFloat = 4
    static let actionHeight: CGFloat = height - inset * 2
    static let actionPaddingX: CGFloat = 11
    static let promptLeading: CGFloat = 11
    static let statusGap: CGFloat = 7
    static let checkSide: CGFloat = 16
    /// Arc caps the prompt at 16rem and ellipsizes the rest.
    static let promptMaxWidth: CGFloat = 256
    /// confirm-morph presses its answers a step deeper than a chip.
    static let actionPressScale: CGFloat = 0.95
    /// While it asks, the danger edge goes from 18 to 24 %.
    static let askingEdge = 0.24
    static var askingEdgeSwatch: Swatch { ArcTone.mix(ArcTone.danger, askingEdge, over: ArcTone.border) }
}

struct IslandMorphPill<Content: View>: View {
    var rim: Color = IslandInk.hairline
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Space.x0_5) { content() }
            .padding(.horizontal, IslandMorphMetrics.inset)
            .frame(height: IslandMorphMetrics.height)
            .background(Capsule().fill(IslandInk.popover))
            .overlay(Capsule().strokeBorder(rim, lineWidth: Stroke.hairline))
    }
}

/// One answer of a confirm pill: its copy key, its fill (nil: plain) and what it does.
struct IslandMorphAnswer {
    let key: String
    let tone: Swatch?
    let action: () -> Void
}

/// An answer inside the pill: secondary is plain text, primary is filled.
struct IslandMorphAction: ButtonStyle {
    enum Role { case secondary, primary(Swatch) }
    let role: Role
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GeistFont.uiCaption.weight(.medium))
            .foregroundStyle(ink(pressed: configuration.isPressed))
            .padding(.horizontal, IslandMorphMetrics.actionPaddingX)
            .frame(height: IslandMorphMetrics.actionHeight)
            .background(Capsule().fill(fill(pressed: configuration.isPressed)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? IslandMorphMetrics.actionPressScale : 1)
            .animation(ArcMotion.press.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private func ink(pressed: Bool) -> Color {
        switch role {
        case .secondary: pressed ? IslandInk.text : IslandInk.secondary
        case .primary: IslandInk.panel
        }
    }

    private func fill(pressed: Bool) -> Color {
        switch role {
        case .secondary: pressed ? IslandInk.chipPressed : Color.clear
        case .primary(let tone): pressed ? ArcTone.mix(ArcTone.foreground, 0.16, over: tone).color : tone.color
        }
    }
}
