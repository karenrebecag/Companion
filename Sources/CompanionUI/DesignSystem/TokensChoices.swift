import AppKit
import CoreText
import SwiftUI

// User-selectable pieces of the design system (accent, typeface). Split from
// Tokens.swift to keep the ramp and the semantic roles readable on their own.

package enum Highlight: String, CaseIterable {
    case standard, blue, green, yellow, pink, orange, purple, white, lime

    package static let key = "companionHighlight"

    package var label: String {
        switch self {
        case .standard: Localized.string("accent.standard")
        case .blue:     Localized.string("accent.blue")
        case .green:    Localized.string("accent.green")
        case .yellow:   Localized.string("accent.yellow")
        case .pink:     Localized.string("accent.pink")
        case .orange:   Localized.string("accent.orange")
        case .purple:   Localized.string("accent.purple")
        case .white:    Localized.string("accent.white")
        case .lime:     Localized.string("accent.lime")
        }
    }

    /// El color plano del énfasis; nil para el default.
    /// Única fuente: swatch y Semantic.accent* derivan de aquí.
    package var ns: NSColor? {
        switch self {
        case .standard: nil
        case .blue:     Accent.blue.ns
        case .green:    Accent.green.ns
        case .yellow:   Accent.yellow.ns
        case .pink:     Accent.pink.ns
        case .orange:   Accent.orange.ns
        case .purple:   Accent.purple.ns
        case .white:    Neutral.white.ns
        case .lime:     Accent.lime.ns
        }
    }

    /// Disco sólido. El default no lo usa: pinta el primary del tema.
    package var swatch: Color {
        ns.map { Color(nsColor: $0) } ?? Semantic.primary
    }

    /// Amarillo, blanco y lima son claros: encima va tinta, no papel.
    package var usesDarkInk: Bool {
        switch self {
        case .yellow, .white, .lime: true
        default: false
        }
    }

    package static var stored: Highlight {
        get {
            Highlight(rawValue:
                UserDefaults.standard.string(forKey: key) ?? "") ?? .standard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(
                name: .companionChromeDidChange, object: nil)
        }
    }
}

/// Swatch hex a Color y NSColor.
package struct Swatch {
    package let hex: String
    package init(_ hex: String) { self.hex = hex }
    package var color: Color { Color(nsColor: ns) }
    package var ns: NSColor { NSColor.fromHex("#" + hex) }
}

/// Roles semánticos que se resuelven según tema claro/oscuro.
/// Escalera ATOM: en dark el fondo es n950, cada piso sube un paso de la rampa.
package enum Semantic {
    // Background + Surface
    package static var background: Color { pair(Palette.canvas, Neutral.n950) }
    package static var surface: Color { pair(Palette.surface, Neutral.n900) }
    package static var surfaceSecondary: Color { pair(Palette.surfaceSecondary, Neutral.n850) }
    package static var surfaceOverlay: Color { pair(Palette.surface, Neutral.n850) }

    // Text
    package static var foreground: Color { pair(Palette.textPrimary, Neutral.n50) }
    /// Neutral fill: Incredible's surface-active (black 5 % over white).
    package static var muted: Color { pair(Swatch("F2F2F2"), Neutral.n850) }
    package static var mutedForeground: Color { pair(Palette.textSecondary, Neutral.n400) }
    /// Group labels and timestamps: Incredible's text-muted.
    package static var textMuted: Color { pair(Palette.textMuted, Neutral.n400) }
    package static var faintForeground: Color { pair(Palette.textFaint, Neutral.n500) }

    // Borders
    /// Menus and popovers: black 8 %, as Incredible's popup border.
    package static var popupBorder: Color { tint(Neutral.black, 0.08, Neutral.white, 0.1) }
    package static var border: Color { pair(Palette.borderDefault, Neutral.n800) }
    package static var borderStrong: Color { pair(Palette.borderInput, Neutral.n700) }
    package static var borderChrome: Color { pair(Palette.borderChrome, Neutral.n800) }

    // Primary: Incredible's solid button is pure black on light.
    package static var primary: Color { pair(Neutral.black, Neutral.n50) }
    package static var primaryForeground: Color { pair(Neutral.n50, Neutral.n950) }
    /// shadcn's hover:bg-primary/90.
    package static var primaryHover: Color { tint(Neutral.black, 0.9, Neutral.n50, 0.9) }
    /// shadcn's hover:bg-secondary/80, over the `muted` fill.
    package static var secondaryHover: Color { pair(Swatch("E9E9E9"), Neutral.n800) }
    /// shadcn's ring/50: the keyboard-focus halo follows the chosen accent.
    package static var focusRing: Color { accent.opacity(0.5) }

    /// Énfasis elegible. Se lee en cada render, así que basta con que la
    /// vista se reevalúe para que el cambio se propague.
    package static var accent: Color {
        Highlight.stored.ns.map { Color(nsColor: $0) } ?? primary
    }

    package static var accentForeground: Color {
        let h = Highlight.stored
        if h == .standard { return primaryForeground }
        return h.usesDarkInk ? Neutral.n950.color : Neutral.white.color
    }

    /// Énfasis como tinta — texto o icono suelto sobre una superficie.
    /// Los acentos claros no se leen sobre fondo claro: en light caen a tinta primaria.
    package static var accentText: Color {
        let h = Highlight.stored
        guard let ns = h.ns else { return primary }
        return h.usesDarkInk ? dynamic(Neutral.n950.ns, ns) : Color(nsColor: ns)
    }

    // Destructive
    package static var destructive: Color { pair(Swatch("DC2626"), Swatch("F87171")) }
    package static var destructiveMuted: Color { pair(Swatch("FAE6E6"), Swatch("1F0E0B")) }
    package static var destructiveForeground: Color { pair(Neutral.white, Neutral.n950) }

    // Status (16l)
    package static var success: Color { pair(Palette.statusGreen, Swatch("30D158")) }
    package static var warning: Color { pair(Palette.statusOrange, Swatch("FF9F0A")) }
    package static var danger: Color { pair(Palette.statusRed, Swatch("FF453A")) }
    package static var link: Color { pair(Palette.link, Swatch("0A84FF")) }
    /// Status at 12 %: the badge and chip backgrounds.
    package static var successMuted: Color { tint(Palette.statusGreen, StateAlpha.statusMuted, Swatch("30D158"), 0.2) }
    package static var warningMuted: Color { tint(Palette.statusOrange, StateAlpha.statusMuted, Swatch("FF9F0A"), 0.2) }
    package static var dangerMuted: Color { tint(Palette.statusRed, StateAlpha.statusMuted, Swatch("FF453A"), 0.2) }
    package static var linkMuted: Color { tint(Palette.link, StateAlpha.statusMuted, Swatch("0A84FF"), 0.2) }

    // States
    /// Menu rows, highlighted rows, pressed wash: Incredible's 5 %.
    package static var hover: Color { tint(Neutral.black, StateAlpha.active, Neutral.n50, 0.08) }
    /// Icon buttons and quiet rows: Incredible's surface-hover, 2 %.
    /// The account chevron: black 35 % on light, as Incredible's.
    package static var chevron: Color { tint(Neutral.black, 0.35, Neutral.white, 0.4) }
    /// The selected sidebar row: black 7 %.
    package static var sidebarSelected: Color { tint(Neutral.black, SidebarMetrics.selectedAlpha, Neutral.n50, 0.1) }
    package static var hoverSubtle: Color { tint(Neutral.black, StateAlpha.hover, Neutral.n50, 0.04) }
    /// The ghost button's fill.
    package static var wash: Color { tint(Neutral.black, StateAlpha.active, Neutral.n50, 0.1) }
    package static var dangerWash: Color {
        tint(Palette.danger, StateAlpha.dangerWash, Swatch("F87171"), 0.16)
    }
    package static var dangerWashHover: Color {
        tint(Palette.danger, StateAlpha.dangerWashHover, Swatch("F87171"), 0.22)
    }
    package static var dangerHover: Color { pair(Palette.dangerHover, Swatch("EF4444")) }
    package static var pressed: Color { tint(Neutral.n950, 0.12, Neutral.n50, 0.16) }
    package static var scrim: Color { tint(Neutral.black, 0.18, Neutral.black, 0.70) }

    private static func pair(_ light: Swatch, _ dark: Swatch) -> Color {
        dynamic(light.ns, dark.ns)
    }

    private static func tint(_ light: Swatch, _ lightAlpha: CGFloat,
                             _ dark: Swatch, _ darkAlpha: CGFloat) -> Color {
        dynamic(light.ns.withAlphaComponent(lightAlpha),
                dark.ns.withAlphaComponent(darkAlpha))
    }

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark : light
        })
    }
}

// Space. Base 4 like Incredible's Tailwind `--spacing`; the half steps are
// the multiples its CSS actually uses (16k).
package enum Space {
    package static let none: CGFloat = 0
    package static let x0: CGFloat = 0
    package static let x0_5: CGFloat = 2
    package static let x1: CGFloat = 4
    package static let x1_5: CGFloat = 6
    package static let x2: CGFloat = 8
    package static let x2_5: CGFloat = 10
    package static let x3: CGFloat = 12
    package static let x3_5: CGFloat = 14
    package static let x4: CGFloat = 16
    package static let x5: CGFloat = 20
    package static let x6: CGFloat = 24
    package static let x7: CGFloat = 28
    package static let x8: CGFloat = 32
    package static let x9: CGFloat = 36
    package static let x10: CGFloat = 40
    package static let x12: CGFloat = 48
    package static let x14: CGFloat = 56
    /// Page side margin.
    package static let gutter: CGFloat = x14
    /// Nested-row indent.
    package static let indent: CGFloat = 18
    /// Closing space under a card's last row.
    package static let cardEnd: CGFloat = x6
    package static let insetTight: CGFloat = x2
    package static let inset: CGFloat = x4
    package static let insetLoose: CGFloat = x6
    package static let stack: CGFloat = x3
    package static let section: CGFloat = x10
    package static let gapXS: CGFloat = x3
    package static let gapS: CGFloat = x4
    package static let gapM: CGFloat = x6
}

// Icon sizes
package enum IconSize {
    package static let dot: CGFloat = 6
    package static let hero: CGFloat = 28
}

// Layout container (R-03). OSMO's system is adimensional fractions of the
// available width; the app adds the one absolute it needs: the centered
// reading column a full-screen sheet lays on.
package enum Container {
    /// OSMO container fractions: .is--m / .is--sm / .is--s.
    package static let m: CGFloat = 0.825
    package static let sm: CGFloat = 0.65
    package static let s: CGFloat = 0.5
    /// The centered reading column for full-screen sheets. Settings keep it
    /// (16k D3): only chat reads at `content`.
    package static let sheet: CGFloat = 520
    /// Incredible's containers (16k).
    package static let narrow: CGFloat = 384
    package static let medium: CGFloat = 448
    package static let wide: CGFloat = 576
    package static let content: CGFloat = 960
    /// Hero figure height inside a sheet.
    package static let hero: CGFloat = 200
    /// The approval sheet: wide enough for a phrase plus its preview,
    /// narrow enough to read as an interruption, not a window (19-1).
    package static let approval: CGFloat = 420
}

// Border radius, Incredible's named corners (16k).
package enum Radius {
    package static let sm: CGFloat = 4
    package static let md: CGFloat = 6
    package static let badge: CGFloat = 8
    package static let chip: CGFloat = 10
    /// Tailwind's rounded-xl (0.75rem): shadcn's chat bubble.
    package static let bubble: CGFloat = 12
    package static let control: CGFloat = 14
    package static let lg: CGFloat = 16
    package static let cardSm: CGFloat = 18
    package static let xl: CGFloat = 20
    package static let dialog: CGFloat = 20
    package static let card: CGFloat = 22
    package static let panel: CGFloat = 28
    package static let full: CGFloat = 100
}

// Control sizes (16k): Incredible's switch and select.
package enum ControlMetrics {
    package static let switchWidth: CGFloat = 38
    package static let switchHeight: CGFloat = 23
    package static let switchThumb: CGFloat = 19
    package static let switchSmallWidth: CGFloat = 28
    package static let switchSmallHeight: CGFloat = 16
    package static let switchSmallThumb: CGFloat = 12
    package static let switchPad: CGFloat = 2
    package static let selectSmallHeight: CGFloat = 34
}

// Type sizes: la escala por papel de Incredible (16k), medida en su CSS.
// Sustituye a la banda OSMO de docs/specs/reticula/01-escala-tipografica.md.
package enum TypeSize {
    /// Piso de plataforma: no hay nada mas abajo.
    package static let micro: CGFloat = 11
    package static let caption: CGFloat = 12
    /// NSFont.systemFontSize.
    package static let body: CGFloat = 13
    package static let rowTitle: CGFloat = 14
    package static let heroBody: CGFloat = 15
    package static let sectionTitle: CGFloat = 16
    package static let dialogTitle: CGFloat = 20
    package static let bannerTitle: CGFloat = 22
    package static let pageTitle: CGFloat = 30
    /// Floor of the fluid display size; see `display(forWidth:)`.
    package static let display: CGFloat = 30
    package static let displayMax: CGFloat = 42

    // Nombres previos, vivos hasta que cada vista pase a su papel (16k-3).
    package static let base: CGFloat = body
    package static let strong: CGFloat = sectionTitle
    package static let title: CGFloat = bannerTitle

    /// Incredible's display grows with the window: 3.2 % of its width,
    /// clamped to 30…42.
    package static func display(forWidth width: CGFloat) -> CGFloat {
        Swift.min(displayMax, Swift.max(display, (width * 0.032).rounded()))
    }
}

// Letter spacing
package enum Tracking {
    package static let tighter: CGFloat = -0.03
    package static let tight: CGFloat = -0.025
    /// Incredible's page and banner titles.
    package static let title: CGFloat = -0.02
    package static let snug: CGFloat = -0.01
    package static let normal: CGFloat = 0
    package static let wide: CGFloat = 0.025
    /// Uppercase labels.
    package static let caps: CGFloat = 0.06
    package static let wider: CGFloat = 0.08
}

// Stroke widths
package enum Stroke {
    package static let hairline: CGFloat = 1
    package static let thin: CGFloat = 1.5
    package static let medium: CGFloat = 2
    /// shadcn's focus-visible:ring-[3px].
    package static let ring: CGFloat = 3
}

// Elevation shadows = Incredible's card / raised / popup / modal (16l), one
// layer each, SwiftUI radius = CSS blur / 2. Rank is the comparable axis.
package enum Elevation: Int, Sendable, CaseIterable, Comparable {
    case rest, hover, panel, sheet, popover

    package static func < (lhs: Elevation, rhs: Elevation) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    package var shadowRadius: CGFloat {
        switch self {
        case .rest: 0
        case .hover: 5
        case .panel: 10
        case .sheet: 24
        case .popover: 50
        }
    }

    package var shadowY: CGFloat {
        switch self {
        case .rest: 0
        case .hover: 4
        case .panel: 6
        case .sheet: 16
        case .popover: 32
        }
    }

    package var shadowOpacity: Double {
        switch self {
        case .rest: 0
        case .hover: 0.04
        case .panel: 0.08
        case .sheet: 0.14
        case .popover: 0.2
        }
    }
}

extension View {
    package func elevation(_ level: Elevation) -> some View {
        shadow(
            color: .black.opacity(level.shadowOpacity),
            radius: level.shadowRadius,
            y: level.shadowY)
    }

    package func elevationChip() -> some View { elevation(.hover) }
    package func elevationPanel() -> some View { elevation(.panel) }
    package func elevationSheet() -> some View { elevation(.sheet) }
}
