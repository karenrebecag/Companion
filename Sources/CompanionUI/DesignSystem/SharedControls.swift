import SwiftUI

// Spec 16p §4.1: the capsule chip and the close button, once. The island
// and the welcome each drew their own chip, and seven screens drew their own
// ×; the look now comes from the surface's ink, not from a copy.

/// How much room a capsule chip takes. The island speaks in captions; the
/// welcome sheet asks its questions a step larger.
package enum ChipDensity: Sendable {
    case compact, regular

    package var paddingX: CGFloat {
        switch self {
        case .compact: Space.x3
        case .regular: Space.x4
        }
    }

    package var paddingY: CGFloat {
        switch self {
        case .compact: Space.x1_5
        case .regular: Space.x2
        }
    }

    var font: Font {
        switch self {
        case .compact: GeistFont.uiCaption
        case .regular: GeistFont.uiLabel
        }
    }
}

/// A chip's ink on its surface: text, rest fill and pressed fill. The rim
/// and the press scale are Arc's, so only the island's inks carry them.
struct ChipInk {
    let text: Color
    let fill: Color
    let pressed: Color
    var rim: Color?
    var pressScale: CGFloat = 1

    /// Arc's ghost control on the black island: surface, a border rim.
    static var island: ChipInk {
        ChipInk(text: IslandInk.text, fill: IslandInk.chip, pressed: IslandInk.chipPressed,
                rim: IslandInk.hairline, pressScale: IslandArc.pressScale)
    }

    /// The question card's Confirm: Arc's primary, accent with dark text.
    static var choiceConfirm: ChipInk {
        ChipInk(text: IslandInk.panel, fill: ArcTone.accent.color,
                pressed: ArcTone.mix(ArcTone.foreground, 0.16, over: ArcTone.accent).color,
                pressScale: IslandArc.pressScale)
    }

    /// confirm-morph's danger: red words on a 4 % red surface, an 18 % red edge.
    static var islandDestructive: ChipInk {
        ChipInk(text: IslandInk.destructive, fill: IslandArc.Danger.fillSwatch.color,
                pressed: IslandArc.Danger.hoverSwatch.color, rim: IslandArc.Danger.edgeSwatch.color,
                pressScale: IslandArc.pressScale)
    }

    /// The welcome's choices: grey, the chosen one inked.
    static func choice(selected: Bool) -> ChipInk {
        selected
            ? ChipInk(text: Semantic.primaryForeground, fill: Semantic.primary, pressed: Semantic.foreground)
            : ChipInk(text: Semantic.foreground, fill: Semantic.muted, pressed: Semantic.pressed)
    }
}

struct CapsuleChipStyle: ButtonStyle {
    let ink: ChipInk
    let density: ChipDensity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(density.font)
            .foregroundStyle(ink.text)
            .padding(.horizontal, density.paddingX)
            .padding(.vertical, density.paddingY)
            .background(Capsule().fill(configuration.isPressed ? ink.pressed : ink.fill))
            .overlay { if let rim = ink.rim { Capsule().strokeBorder(rim, lineWidth: Stroke.hairline) } }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? ink.pressScale : 1)
            // Only Arc's inks give under the finger; the window's chips keep
            // their instant fill.
            .animation(ink.pressScale == 1 ? nil : ArcMotion.press.animation(reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

/// Where a close button sits decides its ink; the size follows the surface.
enum CloseButtonVariant {
    case window, island, onMedia

    var size: IconButtonSize {
        switch self {
        case .window: .close
        case .island: .islandClose
        case .onMedia: .attachmentRemove
        }
    }

    /// Every × gave under the finger before it was shared (PressableStyle).
    var pressable: Bool { true }

    var tone: IconButtonTone {
        switch self {
        case .window: .window
        case .island: .island
        case .onMedia: .onMedia
        }
    }
}

/// The ×. Closing a surface always says the same word; removing a thing
/// passes its own label, because VoiceOver has to name what goes away.
struct CloseButton: View {
    static var label: String { Localized.string("action.close") }

    var variant: CloseButtonVariant = .window
    var label: String = CloseButton.label
    let action: () -> Void

    var body: some View {
        IconButton("xmark", label: label, size: variant.size, tone: variant.tone,
                   pressable: variant.pressable, action: action)
    }
}
