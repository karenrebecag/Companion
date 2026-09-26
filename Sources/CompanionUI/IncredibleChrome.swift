import SwiftUI

// Wave 16l: the measured sizes of Incredible's small controls and the views
// that draw them. Values from docs/research/incredible-componentes.md.

public enum ButtonMetrics {
    public static let height: CGFloat = 40
    public static let padding: CGFloat = Space.x5
    public static let ghostPadding: CGFloat = Space.x4
    public static let heroPaddingX: CGFloat = Space.x6
    public static let heroPaddingY: CGFloat = Space.x3
    public static let hoverScale: CGFloat = 1.03
    public static let welcomeHeight: CGFloat = 46
    public static let welcomePadding: CGFloat = 30
    /// Hover and state changes ride Incredible's settle curve.
    public static let duration = 0.2
}

public struct IconButtonSize: Sendable, Equatable {
    public let side: CGFloat
    public let glyph: CGFloat

    public static let small = IconButtonSize(side: 28, glyph: 16)
    public static let medium = IconButtonSize(side: 34, glyph: 18)
    /// `ui-close`: a 32 circle on the 5 % wash.
    public static let close = IconButtonSize(side: 32, glyph: 14)
}

public enum BadgeMetrics {
    public static let radius: CGFloat = Radius.chip
    public static let paddingX: CGFloat = Space.x2
    public static let paddingY: CGFloat = Space.x0_5
    public static let size: CGFloat = TypeSize.micro
}

public struct KeycapSize: Sendable, Equatable {
    public let radius: CGFloat
    public let paddingX: CGFloat
    public let paddingY: CGFloat
    public let fontSize: CGFloat

    public static let small = KeycapSize(radius: 4, paddingX: 6, paddingY: 2, fontSize: 10)
    public static let large = KeycapSize(radius: 12, paddingX: 16, paddingY: 8, fontSize: 16)
}

/// Round icon-only button: secondary grey, a 2 % wash and primary ink on hover.
public struct IconButton: View {
    let symbol: String
    let label: String
    var size: IconButtonSize = .small
    var danger = false
    /// `chip` corners instead of a circle.
    var chip = false
    let action: () -> Void

    @State private var hovering = false

    public init(_ symbol: String, label: String, size: IconButtonSize = .small,
                danger: Bool = false, chip: Bool = false,
                action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.size = size
        self.danger = danger
        self.chip = chip
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size.glyph * 0.8, weight: .medium))
                .frame(width: size.side, height: size.side)
                .foregroundStyle(ink)
                .background(shape.fill(fill))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(MotionCurve.animation(MotionCurve.standard, MotionTime.fast), value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: chip ? Radius.chip : size.side / 2)
    }

    private var ink: Color {
        guard hovering else { return Semantic.mutedForeground }
        return danger ? Semantic.danger : Semantic.foreground
    }

    private var fill: Color {
        if size == .close { return hovering ? Semantic.hover : Semantic.wash }
        return hovering ? Semantic.hoverSubtle : Color.clear
    }
}

public enum BadgeTone: Sendable {
    case neutral, accent, positive, warning, danger, solid
}

/// Incredible's pill label: chip corners, 11 pt medium.
public struct Badge: View {
    let text: String
    var tone: BadgeTone = .neutral

    public init(_ text: String, tone: BadgeTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(Fonts.sans(BadgeMetrics.size).weight(.medium))
            .lineSpacing(Leading.spacing(Leading.micro, at: BadgeMetrics.size))
            .lineLimit(1)
            .padding(.horizontal, BadgeMetrics.paddingX)
            .padding(.vertical, BadgeMetrics.paddingY)
            .foregroundStyle(ink)
            .background(RoundedRectangle(cornerRadius: BadgeMetrics.radius).fill(fill))
    }

    private var ink: Color {
        switch tone {
        case .neutral: Semantic.mutedForeground
        case .accent: Semantic.link
        case .positive: Semantic.success
        case .warning: Semantic.warning
        case .danger: Semantic.danger
        case .solid: Semantic.surface
        }
    }

    private var fill: Color {
        switch tone {
        case .neutral: Semantic.wash
        case .accent: Semantic.linkMuted
        case .positive: Semantic.successMuted
        case .warning: Semantic.warningMuted
        case .danger: Semantic.dangerMuted
        case .solid: Semantic.foreground
        }
    }
}

/// A key drawn as a key: the small one sits inside rows, the large one in
/// the welcome and shortcut screens.
public struct Keycap: View {
    let text: String
    var size: KeycapSize = .small

    public init(_ text: String, size: KeycapSize = .small) {
        self.text = text
        self.size = size
    }

    public var body: some View {
        Text(text)
            .font(Fonts.sans(size.fontSize).weight(.medium))
            .foregroundStyle(Semantic.foreground)
            .padding(.horizontal, size.paddingX)
            .padding(.vertical, size.paddingY)
            .background(RoundedRectangle(cornerRadius: size.radius).fill(Semantic.surface))
            .overlay(alignment: .bottom) {
                if size == .large {
                    // The lg cap's inset bottom edge: a key has a lip.
                    RoundedRectangle(cornerRadius: size.radius)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: Stroke.medium)
                        .mask(alignment: .bottom) {
                            Rectangle().frame(height: Stroke.medium)
                        }
                }
            }
            .shadow(color: .black.opacity(0.08), radius: size == .large ? 2 : 0,
                    y: size == .large ? 2 : 1)
    }
}
