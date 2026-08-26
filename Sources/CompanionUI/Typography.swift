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

    public static func monoName(bold: Bool, registered: Set<String>) -> String? {
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

    public static var bodyLead: CGFloat { apply(TypeSize.base) * 0.3 }
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

// Font registry. Bundle holds Inter (OFL). Proprietary faces load from
// Application Support if the user dropped them; otherwise Inter then system.
public enum Fonts {
    private static let knownNames = [
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
    // En el piso el tamano ya no diferencia: lo hacen familia, caja y
    // tracking. Ver "presupuesto de canales" en docs/specs/reticula.
    public static var uiEyebrow: Font { Fonts.mono(TypeSize.micro, bold: true) }
    public static var uiMicro: Font { Fonts.sans(TypeSize.micro) }
    public static var uiCaption: Font { Fonts.sans(TypeSize.micro) }
    public static var uiMono: Font { Fonts.mono(TypeSize.micro) }
    public static var uiMonoSm: Font { Fonts.mono(TypeSize.micro) }
    public static var uiAction: Font { Fonts.mono(TypeSize.micro, bold: true) }
    /// Pill CTAs: a hero button cannot whisper at 11 pt.
    public static var uiActionLarge: Font { Fonts.mono(TypeSize.strong, bold: true) }
    public static var uiLabel: Font { Fonts.sans(TypeSize.base) }
    public static var uiBody: Font { Fonts.sans(TypeSize.base) }
    public static var uiCode: Font { Fonts.mono(TypeSize.base) }
    public static var uiSubtitle: Font { Fonts.sans(TypeSize.strong) }
    // Mismo papel con dos nombres; unificarlos es R-04.
    public static var uiTitle: Font { Fonts.sans(TypeSize.title) }
    /// Onboarding hero title: the one place the sheet speaks at display size.
    public static var uiDisplay: Font { Fonts.sans(TypeSize.display) }
    public static var uiHeading: Font { Fonts.sans(TypeSize.title) }
    public static var uiLogo: Font { Fonts.logo(TypeSize.display) }
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
