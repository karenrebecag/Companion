import AppKit
import CoreText
import SwiftUI

// User-selectable pieces of the design system (accent, typeface). Split from
// Tokens.swift to keep the ramp and the semantic roles readable on their own.

public enum Highlight: String, CaseIterable {
    case standard, blue, green, yellow, pink, orange, purple, white, lime

    public static let key = "companionHighlight"

    public var label: String {
        switch self {
        case .standard: "Predeterminado"
        case .blue:     "Azul"
        case .green:    "Verde"
        case .yellow:   "Amarillo"
        case .pink:     "Rosa"
        case .orange:   "Naranja"
        case .purple:   "Morado"
        case .white:    "Blanco"
        case .lime:     "Verde eléctrico"
        }
    }

    /// El color plano del énfasis; nil para el default.
    /// Única fuente: swatch y Semantic.accent* derivan de aquí.
    public var ns: NSColor? {
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
    public var swatch: Color {
        ns.map { Color(nsColor: $0) } ?? Semantic.primary
    }

    /// Amarillo, blanco y lima son claros: encima va tinta, no papel.
    public var usesDarkInk: Bool {
        switch self {
        case .yellow, .white, .lime: true
        default: false
        }
    }

    public static var stored: Highlight {
        get {
            Highlight(rawValue:
                UserDefaults.standard.string(forKey: key) ?? "") ?? .standard
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Swatch hex a Color y NSColor.
public struct Swatch {
    public let hex: String
    public init(_ hex: String) { self.hex = hex }
    public var color: Color { Color(nsColor: ns) }
    public var ns: NSColor { NSColor.fromHex("#" + hex) }
}

/// Roles semánticos que se resuelven según tema claro/oscuro.
/// Escalera ATOM: en dark el fondo es n950, cada piso sube un paso de la rampa.
public enum Semantic {
    // Background + Surface
    public static var background: Color { pair(Neutral.n50, Neutral.n950) }
    public static var surface: Color { pair(Neutral.white, Neutral.n900) }
    public static var surfaceOverlay: Color { pair(Neutral.white, Neutral.n850) }

    // Text
    public static var foreground: Color { pair(Neutral.n950, Neutral.n50) }
    public static var muted: Color { pair(Neutral.n100, Neutral.n850) }
    public static var mutedForeground: Color { pair(Neutral.n600, Neutral.n400) }

    // Borders
    public static var border: Color { pair(Neutral.n200, Neutral.n800) }
    public static var borderStrong: Color { pair(Neutral.n300, Neutral.n700) }

    // Primary (default text color)
    public static var primary: Color { pair(Neutral.n950, Neutral.n50) }
    public static var primaryForeground: Color { pair(Neutral.n50, Neutral.n950) }

    /// Énfasis elegible. Se lee en cada render, así que basta con que la
    /// vista se reevalúe para que el cambio se propague.
    public static var accent: Color {
        Highlight.stored.ns.map { Color(nsColor: $0) } ?? primary
    }

    public static var accentForeground: Color {
        let h = Highlight.stored
        if h == .standard { return primaryForeground }
        return h.usesDarkInk ? Neutral.n950.color : Neutral.white.color
    }

    /// Énfasis como tinta — texto o icono suelto sobre una superficie.
    /// Los acentos claros no se leen sobre fondo claro: en light caen a tinta primaria.
    public static var accentText: Color {
        let h = Highlight.stored
        guard let ns = h.ns else { return primary }
        return h.usesDarkInk ? dynamic(Neutral.n950.ns, ns) : Color(nsColor: ns)
    }

    // Destructive
    public static var destructive: Color { pair(Swatch("DC2626"), Swatch("F87171")) }
    public static var destructiveMuted: Color { pair(Swatch("FAE6E6"), Swatch("1F0E0B")) }
    public static var destructiveForeground: Color { pair(Neutral.white, Neutral.n950) }

    // States
    public static var hover: Color { tint(Neutral.n950, 0.06, Neutral.n50, 0.08) }
    public static var pressed: Color { tint(Neutral.n950, 0.12, Neutral.n50, 0.16) }
    public static var scrim: Color { tint(Neutral.black, 0.18, Neutral.black, 0.70) }

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

// Space
public enum Space {
    public static let none: CGFloat = 0
    public static let x1: CGFloat = 4
    public static let x2: CGFloat = 8
    public static let x3: CGFloat = 12
    public static let x4: CGFloat = 16
    public static let x5: CGFloat = 20
    public static let x6: CGFloat = 24
    public static let x8: CGFloat = 32
    public static let insetTight: CGFloat = x2
    public static let inset: CGFloat = x4
    public static let insetLoose: CGFloat = x6
    public static let stack: CGFloat = x3
    public static let section: CGFloat = x6
    public static let gapXS: CGFloat = x3
    public static let gapS: CGFloat = x4
    public static let gapM: CGFloat = x6
}

// Icon sizes
public enum IconSize {
    public static let dot: CGFloat = 6
    public static let hero: CGFloat = 28
}

// Border radius
public enum Radius {
    public static let sm: CGFloat = 4
    public static let md: CGFloat = 8
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 16
    public static let full: CGFloat = 100
}

// Type sizes (tercera mayor 16·1.25^n)
public enum TypeSize {
    public static let xs: CGFloat = 10.24
    public static let sm: CGFloat = 12.8
    public static let base: CGFloat = 16
    public static let md: CGFloat = 18
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 25
    public static let display: CGFloat = 31.25
}

// Letter spacing
public enum Tracking {
    public static let tighter: CGFloat = -0.03
    public static let tight: CGFloat = -0.02
    public static let snug: CGFloat = -0.01
    public static let normal: CGFloat = 0
    public static let wide: CGFloat = 0.06
    public static let wider: CGFloat = 0.08
}

// Stroke widths
public enum Stroke {
    public static let hairline: CGFloat = 1
    public static let thin: CGFloat = 1.5
    public static let medium: CGFloat = 2
}

// Elevation shadows. Rank is the comparable axis; radius must not shrink.
public enum Elevation: Int, Sendable, CaseIterable, Comparable {
    case rest, hover, panel, sheet, popover

    public static func < (lhs: Elevation, rhs: Elevation) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var shadowRadius: CGFloat {
        switch self {
        case .rest: 0
        case .hover: 3
        case .panel: 24
        case .sheet: 32
        case .popover: 40
        }
    }

    public var shadowY: CGFloat {
        switch self {
        case .rest: 0
        case .hover: 1
        case .panel: 10
        case .sheet: 14
        case .popover: 18
        }
    }

    public var shadowOpacity: Double {
        switch self {
        case .rest: 0
        case .hover: 0.15
        case .panel: 0.22
        case .sheet: 0.3
        case .popover: 0.34
        }
    }
}

extension View {
    public func elevation(_ level: Elevation) -> some View {
        shadow(
            color: .black.opacity(level.shadowOpacity),
            radius: level.shadowRadius,
            y: level.shadowY)
    }

    public func elevationChip() -> some View { elevation(.hover) }
    public func elevationPanel() -> some View { elevation(.panel) }
    public func elevationSheet() -> some View { elevation(.sheet) }
}

// Type families
public enum TypeFamily {
    public static let sans = "Hypodermic"
    public static let logo = "Gadey"
    public static let mono = "TBJ Interval"
}

/// Resolves a requested face against what is actually registered.
/// Proprietary fonts stay local; missing ones fall to Inter, then the system.
public enum FontFallback: Sendable {
    public static func postScriptName(
        _ wanted: AppTypeface, registered: Set<String>
    ) -> String? {
        switch wanted {
        case .serif:
            return nil
        case .inter:
            return registered.contains("Inter-Regular") ? "Inter-Regular" : nil
        case .hypodermic:
            if registered.contains("Hypodermic-Regular") {
                return "Hypodermic-Regular"
            }
            return postScriptName(.inter, registered: registered)
        }
    }

    public static func logoName(registered: Set<String>) -> String? {
        if registered.contains("Gadey") { return "Gadey" }
        return postScriptName(.inter, registered: registered)
    }

    public static func monoName(bold: Bool, registered: Set<String>) -> String? {
        let wanted = bold ? "TBJInterval-Bold" : "TBJInterval-Regular"
        if registered.contains(wanted) { return wanted }
        return postScriptName(.inter, registered: registered)
    }
}

// Typeface selection
public enum AppTypeface: String, CaseIterable {
    case inter, hypodermic, serif

    public static let key = "companionTypeface"

    public var label: String {
        switch self {
        case .inter: "Inter"
        case .hypodermic: "Hypodermic"
        case .serif: "Serif"
        }
    }

    public static var stored: AppTypeface {
        get {
            AppTypeface(rawValue:
                UserDefaults.standard.string(forKey: key) ?? "") ?? .inter
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

// Type scale
public enum TypeScale {
    public static let key = "companionFontDelta"
    public static let min = -2
    public static let max = 3
    public static let origin = -3
    private static let migratedKey = "companionFontDeltaV2"

    public static var delta: Int {
        get {
            migrateIfNeeded()
            let v = UserDefaults.standard.object(forKey: key) as? Int ?? 0
            return Swift.min(max, Swift.max(min, v))
        }
        set {
            UserDefaults.standard.set(Swift.min(max, Swift.max(min, newValue)),
                                      forKey: key)
        }
    }

    public static let floor: CGFloat = 12

    public static func apply(_ size: CGFloat) -> CGFloat {
        Swift.max(Self.floor, size + CGFloat(origin + delta))
    }

    public static var bodyLead: CGFloat { apply(TypeSize.base) * 0.3 }
    public static var codeLead: CGFloat { apply(TypeSize.base) * 0.15 }

    private static func migrateIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: migratedKey) else { return }
        if let old = d.object(forKey: key) as? Int {
            d.set(Swift.min(max, Swift.max(min, old - origin)), forKey: key)
        }
        d.set(true, forKey: migratedKey)
    }
}

// Font registry. Bundle holds Inter (OFL). Proprietary faces load from
// Application Support if the user dropped them; otherwise Inter then system.
public enum Fonts {
    private static let knownNames = [
        "Inter-Regular", "Hypodermic-Regular", "Gadey",
        "TBJInterval-Regular", "TBJInterval-Bold",
    ]
    private static var registered: Set<String> = []

    public static func register() {
        var dirs: [URL] = []
        if let bundled = Bundle.module.resourceURL?
            .appendingPathComponent("Fonts")
        {
            dirs.append(bundled)
        }
        if let main = Bundle.main.resourceURL?
            .appendingPathComponent("Fonts")
        {
            dirs.append(main)
        }
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/Fonts")
        dirs.append(support)
        dirs.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts"))
        for dir in dirs { registerDirectory(dir) }
        refreshRegistered()
    }

    private static func registerDirectory(_ dir: URL) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
        } catch {
            return
        }
        for url in files {
            let ext = url.pathExtension.lowercased()
            guard ext == "otf" || ext == "ttf" else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static func refreshRegistered() {
        registered = Set(knownNames.filter { NSFont(name: $0, size: 12) != nil })
    }

    public static func sans(_ size: CGFloat) -> Font {
        sample(AppTypeface.stored, size: size)
    }

    public static func sample(_ face: AppTypeface, size: CGFloat) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.postScriptName(face, registered: registered) {
            return Font.custom(name, size: s)
        }
        if face == .serif {
            return Font.system(size: s, design: .serif)
        }
        return Font.system(size: s)
    }

    public static func logo(_ size: CGFloat) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.logoName(registered: registered) {
            return Font.custom(name, size: s)
        }
        return Font.system(size: s, weight: .medium)
    }

    public static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.monoName(bold: bold, registered: registered) {
            return Font.custom(name, size: s)
        }
        return Font.system(size: s, design: .monospaced)
            .weight(bold ? .bold : .regular)
    }
}

// Font styles
extension Font {
    public static var uiEyebrow: Font { Fonts.mono(TypeSize.sm, bold: true) }
    public static var uiMicro: Font { Fonts.sans(TypeSize.xs) }
    public static var uiCaption: Font { Fonts.sans(TypeSize.sm) }
    public static var uiLabel: Font { Fonts.sans(TypeSize.sm) }
    public static var uiBody: Font { Fonts.sans(TypeSize.base) }
    public static var uiSubtitle: Font { Fonts.sans(TypeSize.md) }
    public static var uiTitle: Font { Fonts.sans(TypeSize.lg) }
    public static var uiHeading: Font { Fonts.sans(TypeSize.xl) }
    public static var uiLogo: Font { Fonts.logo(TypeSize.display) }
    public static var uiMono: Font { Fonts.mono(TypeSize.sm) }
    public static var uiMonoSm: Font { Fonts.mono(TypeSize.xs) }
    public static var uiCode: Font { Fonts.mono(TypeSize.base) }
    public static var uiAction: Font { Fonts.mono(TypeSize.sm, bold: true) }
}

// Type styling for Views
extension View {
    /// Group header: marks where a section begins without competing with row titles.
    public func typeEyebrow() -> some View {
        font(.uiEyebrow)
            .textCase(.uppercase)
            .tracking(Tracking.wider, at: TypeSize.sm)
            .foregroundStyle(Semantic.mutedForeground)
    }

    /// Large sizes need to close space or they look loose.
    public func typeHeading() -> some View {
        font(.uiHeading).tracking(Tracking.tight, at: TypeSize.xl)
    }

    public func typeTitle() -> some View {
        font(.uiTitle).tracking(Tracking.tight, at: TypeSize.lg)
    }

    public func typeSubtitle() -> some View {
        font(.uiSubtitle).tracking(Tracking.snug, at: TypeSize.md)
    }

    /// Letter spacing in em units; SwiftUI wants points.
    public func tracking(_ em: CGFloat, at size: CGFloat) -> some View {
        tracking(em * TypeScale.apply(size))
    }
}
