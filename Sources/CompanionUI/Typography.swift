import SwiftUI

// Typography half of the design tokens: families, fallbacks, scale and the
// View helpers. Split out of TokensChoices when it crossed the 400-line gate;
// colour, space and elevation stayed there. One system, two files.

// Type families
public enum TypeFamily {
    public static let sans = "Hypodermic"
    public static let logo = "Gadey"
    public static let mono = "TBJ Interval"
}

/// Which face a surface speaks (16k-2): Incredible's window uses the system
/// face; its island and welcome use Geist.
public enum FontFace: Sendable {
    case system, geist
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
        case .interval:
            if registered.contains("TBJInterval-Regular") {
                return "TBJInterval-Regular"
            }
            return postScriptName(.inter, registered: registered)
        case .hypodermic:
            if registered.contains("Hypodermic-Regular") {
                return "Hypodermic-Regular"
            }
            return postScriptName(.inter, registered: registered)
        case .gadey:
            if registered.contains("Gadey") { return "Gadey" }
            return postScriptName(.inter, registered: registered)
        }
    }

    public static func logoName(registered: Set<String>) -> String? {
        if registered.contains("Gadey") { return "Gadey" }
        return postScriptName(.inter, registered: registered)
    }

    /// Wave 16c: Geist is the product's face, as in Incredible — a family
    /// name, so SwiftUI's `.weight` picks Medium/SemiBold/Bold inside it.
    public static func sansFamily(registered: Set<String>) -> String? {
        sansFamily(for: .geist, registered: registered)
    }

    /// nil means the system face.
    public static func sansFamily(for face: FontFace, registered: Set<String>) -> String? {
        guard face == .geist else { return nil }
        if registered.contains("Geist-Regular") { return "Geist" }
        return postScriptName(.inter, registered: registered)
    }

    public static func monoName(bold: Bool, registered: Set<String>) -> String? {
        let geist = bold ? "GeistMono-Medium" : "GeistMono-Regular"
        if registered.contains(geist) { return geist }
        let wanted = bold ? "TBJInterval-Bold" : "TBJInterval-Regular"
        if registered.contains(wanted) { return wanted }
        return postScriptName(.inter, registered: registered)
    }
}

// Typeface selection
public enum AppTypeface: String, CaseIterable {
    case inter, interval, hypodermic, gadey, serif

    public static let key = "companionTypeface"

    public var label: String {
        switch self {
        case .inter: "Inter"
        case .interval: "TBJ Interval"
        case .hypodermic: "Hypodermic"
        case .gadey: "Gadey"
        case .serif: "Serif"
        }
    }

    public static var stored: AppTypeface {
        get {
            AppTypeface(rawValue:
                UserDefaults.standard.string(forKey: key) ?? "") ?? .inter
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(
                name: .companionChromeDidChange, object: nil)
        }
    }
}

// Type scale
public enum TypeScale {
    public static let key = "companionFontDelta"
    /// -2 no existe: con el cuerpo ya en el piso de plataforma no hay a
    /// donde bajar sin fundir dos escalones en uno.
    public static let min = -1
    public static let max = 3
    private static let migratedKey = "companionFontDeltaV3"
    /// Razon por paso. El control es multiplicativo y no aditivo: sumar un
    /// offset conserva las diferencias absolutas y destruye las razones en
    /// los extremos — es lo que fundia micro y base en un solo valor.
    private static let step = 1.08

    public static var delta: Int {
        get {
            migrateIfNeeded()
            let v = UserDefaults.standard.object(forKey: key) as? Int ?? 0
            return Swift.min(max, Swift.max(min, v))
        }
        set {
            UserDefaults.standard.set(Swift.min(max, Swift.max(min, newValue)),
                                      forKey: key)
            NotificationCenter.default.post(
                name: .companionChromeDidChange, object: nil)
        }
    }

    /// NSFont caption2. Solo actua en el paso minimo; ese es todo su papel.
    public static let floor: CGFloat = 10

    public static func apply(_ size: CGFloat) -> CGFloat {
        let scaled = size * CGFloat(pow(step, Double(delta)))
        return Swift.max(Self.floor, scaled.rounded())
    }

    @discardableResult
    public static func nudge(_ step: Int) -> Int {
        delta = Swift.min(max, Swift.max(min, delta + step))
        return delta
    }

    public static func displayLabel(_ value: Int) -> String {
        if value == 0 { return "0" }
        if value > 0 { return "+\(value)" }
        return "−\(abs(value))"
    }

    public static var bodyLead: CGFloat {
        Leading.spacing(Leading.body, at: apply(TypeSize.body))
    }
    public static var codeLead: CGFloat { apply(TypeSize.base) * 0.15 }

    /// Alto de una linea de cuerpo ya renderizada. Un caret o el hueco de una
    /// frase tienen que seguir al texto: con un token de espacio fijo se
    /// quedarian cortos en cuanto el usuario sube el tamano.
    public static var bodyLine: CGFloat { apply(TypeSize.base) + bodyLead }

    private static func migrateIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: migratedKey) else { return }
        if let old = d.object(forKey: key) as? Int {
            // Bajo el origen -3 el nominal era +3; ahora el nominal es 0.
            // Sin esto convivian dos poblaciones viendo escalas distintas.
            d.set(Swift.min(max, Swift.max(min, old - 3)), forKey: key)
        }
        d.set(true, forKey: migratedKey)
    }
}

// Line height per role (16k), as Incredible's CSS ratios.
public enum Leading {
    public static let micro: CGFloat = 1.35
    public static let caption: CGFloat = 1.4
    public static let body: CGFloat = 1.5
    public static let rowTitle: CGFloat = 1.4
    public static let heroBody: CGFloat = 1.5
    public static let sectionTitle: CGFloat = 1.3
    public static let dialogTitle: CGFloat = 1.2
    public static let bannerTitle: CGFloat = 1.2
    public static let pageTitle: CGFloat = 1.2
    public static let display: CGFloat = 1.06

    public static let tight: CGFloat = 1.25
    public static let snug: CGFloat = 1.375
    public static let normal: CGFloat = 1.5
    public static let relaxed: CGFloat = 1.625

    /// CSS gives the whole line box; SwiftUI's `lineSpacing` only the gap
    /// added between lines, so the font size itself comes off.
    public static func spacing(_ ratio: CGFloat, at size: CGFloat) -> CGFloat {
        Swift.max(0, size * (ratio - 1))
    }
}

// Font registry. Bundle holds Inter (OFL). Proprietary faces load from
// Application Support if the user dropped them; otherwise Inter then system.
public enum Fonts {
    private static let knownNames = [
        "Geist-Regular", "GeistMono-Regular", "GeistMono-Medium",
        "Inter-Regular", "Hypodermic-Regular", "Gadey",
        "TBJInterval-Regular", "TBJInterval-Bold", "TBJInterval-Light",
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

    /// The window's face: the system one, as Incredible's main window (16k-2).
    public static func sans(_ size: CGFloat) -> Font {
        sans(size, face: .system)
    }

    /// The island and the welcome sheet speak Geist.
    public static func geist(_ size: CGFloat) -> Font {
        sans(size, face: .geist)
    }

    public static func sans(_ size: CGFloat, face: FontFace) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.sansFamily(for: face, registered: registered) {
            return Font.custom(name, size: s)
        }
        return Font.system(size: s)  // token-exempt: the font factory is the one place that calls .system
    }

    public static func sample(_ face: AppTypeface, size: CGFloat) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.postScriptName(face, registered: registered) {
            return Font.custom(name, size: s)
        }
        if face == .serif {
            return Font.system(size: s, design: .serif)  // token-exempt: the font factory is the one place that calls .system
        }
        return Font.system(size: s)  // token-exempt: the font factory is the one place that calls .system
    }

    public static func logo(_ size: CGFloat) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.logoName(registered: registered) {
            return Font.custom(name, size: s)
        }
        return Font.system(size: s, weight: .medium)  // token-exempt: the font factory is the one place that calls .system
    }

    /// SF Symbols: the system font at the user's scale, where the symbol's
    /// weight is honoured.
    public static func symbol(_ size: CGFloat, weight: Font.Weight) -> Font {
        Font.system(size: TypeScale.apply(size), weight: weight)  // token-exempt: the font factory is the one place that calls .system
    }

    public static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.monoName(bold: bold, registered: registered) {
            return Font.custom(name, size: s)
        }
        return Font.system(size: s, design: .monospaced)  // token-exempt: the font factory is the one place that calls .system
            .weight(bold ? .bold : .regular)
    }
}

// Font styles
extension Font {
    // En el piso el tamano ya no diferencia: lo hacen familia, caja y
    // tracking. Ver "presupuesto de canales" en docs/specs/reticula.
    public static var uiEyebrow: Font { Fonts.mono(TypeSize.micro, bold: true) }
    public static var uiMicro: Font { Fonts.sans(TypeSize.micro) }
    public static var uiCaption: Font { Fonts.sans(TypeSize.micro) }
    public static var uiMono: Font { Fonts.mono(TypeSize.micro) }
    public static var uiMonoSm: Font { Fonts.mono(TypeSize.micro) }
    public static var uiAction: Font { Fonts.mono(TypeSize.micro, bold: true) }
    /// Pill CTAs: a hero button cannot whisper at 11 pt, and at this size the
    /// mono action face fights the sheet — sans carries it.
    public static var uiCta: Font { Fonts.sans(TypeSize.strong) }
    public static var uiLabel: Font { Fonts.sans(TypeSize.base) }
    public static var uiBody: Font { Fonts.sans(TypeSize.base) }
    public static var uiCode: Font { Fonts.mono(TypeSize.base) }
    public static var uiSubtitle: Font { Fonts.sans(TypeSize.strong) }
    // Mismo papel con dos nombres; unificarlos es R-04.
    public static var uiTitle: Font { Fonts.sans(TypeSize.title) }
    /// Hero title: the one place a sheet speaks at display size.
    public static var uiDisplay: Font { Fonts.sans(TypeSize.display) }
    public static var uiHeading: Font { Fonts.sans(TypeSize.title) }
    public static var uiLogo: Font { Fonts.logo(TypeSize.display) }
}

/// The same roles in Geist, for the island, the welcome sheet and the
/// approval panel (16k-2).
public enum GeistFont {
    public static var uiMicro: Font { Fonts.geist(TypeSize.micro) }
    public static var uiCaption: Font { Fonts.geist(TypeSize.micro) }
    public static var uiCta: Font { Fonts.geist(TypeSize.strong) }
    public static var uiLabel: Font { Fonts.geist(TypeSize.base) }
    public static var uiBody: Font { Fonts.geist(TypeSize.base) }
    public static var uiSubtitle: Font { Fonts.geist(TypeSize.strong) }
    public static var uiTitle: Font { Fonts.geist(TypeSize.title) }
    public static var uiDisplay: Font { Fonts.geist(TypeSize.display) }
    public static var uiHeading: Font { Fonts.geist(TypeSize.title) }
}

// Type styling for Views
extension View {
    /// Group header: marks where a section begins without competing with row titles.
    public func typeEyebrow() -> some View {
        font(.uiEyebrow)
            .textCase(.uppercase)
            .tracking(Tracking.wider, at: TypeSize.micro)
            .foregroundStyle(Semantic.mutedForeground)
    }

    /// Large sizes need to close space or they look loose.
    public func typeHeading() -> some View {
        font(.uiHeading).tracking(Tracking.tight, at: TypeSize.title)
    }

    public func typeTitle() -> some View {
        font(.uiTitle).tracking(Tracking.tight, at: TypeSize.title)
    }

    public func typeSubtitle() -> some View {
        font(.uiSubtitle).tracking(Tracking.snug, at: TypeSize.strong)
    }

    /// Letter spacing in em units; SwiftUI wants points.
    public func tracking(_ em: CGFloat, at size: CGFloat) -> some View {
        tracking(em * TypeScale.apply(size))
    }
}
