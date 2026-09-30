import AppKit
import SwiftUI

// Typography half of the design tokens: families, fallbacks, scale and the
// View helpers. Split out of TokensChoices when it crossed the 400-line gate;
// colour, space and elevation stayed there. One system, two files.

// Type families
package enum TypeFamily {
    package static let sans = "Hypodermic"
    package static let logo = "Gadey"
    package static let mono = "TBJ Interval"
}

/// Which face a surface speaks (16k-2): Incredible's window uses the system
/// face; its island and welcome use Geist.
package enum FontFace: Sendable {
    case system, geist
}

/// Resolves a requested face against what is actually registered.
/// Proprietary fonts stay local; missing ones fall to Inter, then the system.
package enum FontFallback: Sendable {
    package static func postScriptName(
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

    package static func logoName(registered: Set<String>) -> String? {
        if registered.contains("Gadey") { return "Gadey" }
        return postScriptName(.inter, registered: registered)
    }

    /// Wave 16c: Geist is the product's face, as in Incredible — a family
    /// name, so SwiftUI's `.weight` picks Medium/SemiBold/Bold inside it.
    package static func sansFamily(registered: Set<String>) -> String? {
        sansFamily(for: .geist, registered: registered)
    }

    /// nil means the system face.
    package static func sansFamily(for face: FontFace, registered: Set<String>) -> String? {
        guard face == .geist else { return nil }
        if registered.contains("Geist-Regular") { return "Geist" }
        return postScriptName(.inter, registered: registered)
    }

    package static func monoName(bold: Bool, registered: Set<String>) -> String? {
        let geist = bold ? "GeistMono-Medium" : "GeistMono-Regular"
        if registered.contains(geist) { return geist }
        let wanted = bold ? "TBJInterval-Bold" : "TBJInterval-Regular"
        if registered.contains(wanted) { return wanted }
        return postScriptName(.inter, registered: registered)
    }
}

// Typeface selection
package enum AppTypeface: String, CaseIterable {
    case inter, interval, hypodermic, gadey, serif

    package static let key = "companionTypeface"

    package var label: String {
        switch self {
        case .inter: "Inter"
        case .interval: "TBJ Interval"
        case .hypodermic: "Hypodermic"
        case .gadey: "Gadey"
        case .serif: "Serif"
        }
    }

    package static var stored: AppTypeface {
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
package enum TypeScale {
    package static let key = "companionFontDelta"
    /// -2 no existe: con el cuerpo ya en el piso de plataforma no hay a
    /// donde bajar sin fundir dos escalones en uno.
    package static let min = -1
    package static let max = 3
    private static let migratedKey = "companionFontDeltaV3"
    /// Razon por paso. El control es multiplicativo y no aditivo: sumar un
    /// offset conserva las diferencias absolutas y destruye las razones en
    /// los extremos — es lo que fundia micro y base en un solo valor.
    private static let step = 1.08

    package static var delta: Int {
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
    package static let floor: CGFloat = 10

    package static func apply(_ size: CGFloat) -> CGFloat {
        let scaled = size * CGFloat(pow(step, Double(delta)))
        return Swift.max(Self.floor, scaled.rounded())
    }

    @discardableResult
    package static func nudge(_ step: Int) -> Int {
        delta = Swift.min(max, Swift.max(min, delta + step))
        return delta
    }

    package static func displayLabel(_ value: Int) -> String {
        if value == 0 { return "0" }
        if value > 0 { return "+\(value)" }
        return "−\(abs(value))"
    }

    package static var bodyLead: CGFloat {
        Leading.spacing(Leading.body, at: apply(TypeSize.body))
    }
    package static var codeLead: CGFloat { apply(TypeSize.base) * 0.15 }

    /// Alto de una linea de cuerpo ya renderizada. Un caret o el hueco de una
    /// frase tienen que seguir al texto: con un token de espacio fijo se
    /// quedarian cortos en cuanto el usuario sube el tamano.
    package static var bodyLine: CGFloat { apply(TypeSize.base) + bodyLead }

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
package enum Leading {
    package static let micro: CGFloat = 1.35
    package static let caption: CGFloat = 1.4
    package static let body: CGFloat = 1.5
    package static let rowTitle: CGFloat = 1.4
    package static let heroBody: CGFloat = 1.5
    package static let sectionTitle: CGFloat = 1.3
    package static let dialogTitle: CGFloat = 1.2
    package static let bannerTitle: CGFloat = 1.2
    package static let pageTitle: CGFloat = 1.2
    package static let display: CGFloat = 1.06

    package static let tight: CGFloat = 1.25
    package static let snug: CGFloat = 1.375
    package static let normal: CGFloat = 1.5
    package static let relaxed: CGFloat = 1.625

    /// CSS gives the whole line box; SwiftUI's `lineSpacing` only the gap
    /// added between lines, so the font size itself comes off.
    package static func spacing(_ ratio: CGFloat, at size: CGFloat) -> CGFloat {
        Swift.max(0, size * (ratio - 1))
    }

    /// SwiftUI adds `lineSpacing` on top of the font's own line height (about
    /// 1.2 x the size in SF), so the gap that lands a line on `ratio * size`
    /// is what is left after that natural height. Never below zero: SwiftUI
    /// ignores a negative `lineSpacing`, so a ratio tighter than the font's own
    /// line (display, 1.06) bottoms out at the natural height.
    package static func spacing(_ ratio: CGFloat, at size: CGFloat, face: FontFace) -> CGFloat {
        Swift.max(0, ratio * size - naturalHeight(size, face: face))
    }

    /// The face's own line box at a size. AppKit's attributed-string size is
    /// what SwiftUI's Text lays out, to the point: NSLayoutManager and raw
    /// CoreText metrics both disagree with it at several sizes.
    package static func naturalHeight(_ size: CGFloat, face: FontFace = .system) -> CGFloat {
        let font: NSFont
        switch face {
        case .system: font = NSFont.systemFont(ofSize: size)
        case .geist: font = NSFont(name: "Geist-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
        }
        return NSAttributedString(string: "Ag", attributes: [.font: font]).size().height
    }
}

/// A type role: the size and the line height Incredible pairs with it. The
/// font factory only knows sizes; a role is what lets a multi-line text ask
/// for both from one name. Note `TypeRole.caption` is 12 pt, while
/// `Font.uiCaption` is the 11 pt step (`.micro`): use `typeRole(.micro)` for it.
package enum TypeRole: CaseIterable, Sendable {
    case micro, caption, body, rowTitle, heroBody, sectionTitle
    case dialogTitle, bannerTitle, pageTitle, display

    package var size: CGFloat {
        switch self {
        case .micro: TypeSize.micro
        case .caption: TypeSize.caption
        case .body: TypeSize.body
        case .rowTitle: TypeSize.rowTitle
        case .heroBody: TypeSize.heroBody
        case .sectionTitle: TypeSize.sectionTitle
        case .dialogTitle: TypeSize.dialogTitle
        case .bannerTitle: TypeSize.bannerTitle
        case .pageTitle: TypeSize.pageTitle
        case .display: TypeSize.display
        }
    }

    package var leading: CGFloat {
        switch self {
        case .micro: Leading.micro
        case .caption: Leading.caption
        case .body: Leading.body
        case .rowTitle: Leading.rowTitle
        case .heroBody: Leading.heroBody
        case .sectionTitle: Leading.sectionTitle
        case .dialogTitle: Leading.dialogTitle
        case .bannerTitle: Leading.bannerTitle
        case .pageTitle: Leading.pageTitle
        case .display: Leading.display
        }
    }

    /// Takes the size as rendered, after the user's scale: the gap is a share
    /// of what is on screen, not of the nominal size.
    package func lineSpacing(atScaledSize scaled: CGFloat, face: FontFace = .system) -> CGFloat {
        Leading.spacing(leading, at: scaled, face: face)
    }

    /// The gap for this role at the user's current scale.
    package func lineSpacing(face: FontFace = .system) -> CGFloat {
        lineSpacing(atScaledSize: TypeScale.apply(size), face: face)
    }
}

extension View {
    /// The gap between lines that gives a role its measured line height.
    package func typeLeading(_ role: TypeRole, face: FontFace = .system) -> some View {
        lineSpacing(role.lineSpacing(face: face))
    }

    /// Font and line height from one role, so a text cannot get one role's
    /// size with another's leading.
    package func typeRole(_ role: TypeRole, face: FontFace = .system) -> some View {
        font(Fonts.sans(role.size, face: face)).typeLeading(role, face: face)
    }
}

// Font registry. Bundle holds Inter (OFL). Proprietary faces load from
// Application Support if the user dropped them; otherwise Inter then system.
package enum Fonts {
    private static let knownNames = [
        "Geist-Regular", "GeistMono-Regular", "GeistMono-Medium",
        "Inter-Regular", "Hypodermic-Regular", "Gadey",
        "TBJInterval-Regular", "TBJInterval-Bold", "TBJInterval-Light",
    ]
    private static var registered: Set<String> = []

    /// A nil `bundle` (not found, 21c) only drops that folder: the user's
    /// folders still register and anything missing falls back to the system.
    package static func register(bundle: Bundle? = UIResourceBundle.bundle) {
        let bundled = bundledDirectories(bundle: bundle)
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Companion/Fonts")
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts")
        for url in filesToRegister(bundled: bundled, user: [support, library]) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        refreshRegistered()
    }

    /// Only bundled folders are deduped against each other: a user font that
    /// shares a bundled file name is the user's override and registered as it
    /// was before 21c.
    static func filesToRegister(bundled: [URL], user: [URL]) -> [URL] {
        fontFiles(in: bundled) + user.flatMap { fontFiles(in: [$0]) }
    }

    /// The SwiftPM bundle is the only bundled copy (21c S2): bundle.sh no
    /// longer duplicates the fonts into `Contents/Resources/Fonts`.
    static func bundledDirectories(bundle: Bundle?) -> [URL] {
        [bundle?.resourceURL?.appendingPathComponent("Fonts")].compactMap { $0 }
    }

    /// Font files across `dirs`, one per file name, first folder wins.
    /// CoreText rejects the same path twice (error 105) but registers a copy
    /// at another path as a second face (checked 2026-09-30, macOS 26).
    static func fontFiles(in dirs: [URL]) -> [URL] {
        var seen: Set<String> = []
        var files: [URL] = []
        for dir in dirs {
            let entries: [URL]
            do {
                entries = try FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil)
            } catch {
                continue
            }
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let ext = url.pathExtension.lowercased()
                guard ext == "otf" || ext == "ttf", seen.insert(url.lastPathComponent).inserted else { continue }
                files.append(url)
            }
        }
        return files
    }

    private static func refreshRegistered() {
        registered = Set(knownNames.filter { NSFont(name: $0, size: 12) != nil })
    }

    /// The window's face: the system one, as Incredible's main window (16k-2).
    package static func sans(_ size: CGFloat) -> Font {
        sans(size, face: .system)
    }

    /// The island and the welcome sheet speak Geist.
    package static func geist(_ size: CGFloat) -> Font {
        sans(size, face: .geist)
    }

    package static func sans(_ size: CGFloat, face: FontFace) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.sansFamily(for: face, registered: registered) {
            return Font.custom(name, size: s)
        }
        return Font.system(size: s)  // token-exempt: the font factory is the one place that calls .system
    }

    package static func sample(_ face: AppTypeface, size: CGFloat) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.postScriptName(face, registered: registered) {
            return Font.custom(name, size: s)
        }
        if face == .serif {
            return Font.system(size: s, design: .serif)  // token-exempt: the font factory is the one place that calls .system
        }
        return Font.system(size: s)  // token-exempt: the font factory is the one place that calls .system
    }

    package static func logo(_ size: CGFloat) -> Font {
        let s = TypeScale.apply(size)
        if let name = FontFallback.logoName(registered: registered) {
            return Font.custom(name, size: s)
        }
        return Font.system(size: s, weight: .medium)  // token-exempt: the font factory is the one place that calls .system
    }

    /// SF Symbols: the system font at the user's scale, where the symbol's
    /// weight is honoured.
    package static func symbol(_ size: CGFloat, weight: Font.Weight) -> Font {
        Font.system(size: TypeScale.apply(size), weight: weight)  // token-exempt: the font factory is the one place that calls .system
    }

    package static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
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
    package static var uiEyebrow: Font { Fonts.mono(TypeSize.micro, bold: true) }
    package static var uiMicro: Font { Fonts.sans(TypeSize.micro) }
    /// The 11 pt step, i.e. `TypeRole.micro`; `TypeRole.caption` is 12 pt.
    package static var uiCaption: Font { Fonts.sans(TypeSize.micro) }
    package static var uiMono: Font { Fonts.mono(TypeSize.micro) }
    package static var uiMonoSm: Font { Fonts.mono(TypeSize.micro) }
    package static var uiAction: Font { Fonts.mono(TypeSize.micro, bold: true) }
    /// Pill CTAs: a hero button cannot whisper at 11 pt, and at this size the
    /// mono action face fights the sheet — sans carries it.
    package static var uiCta: Font { Fonts.sans(TypeSize.strong) }
    package static var uiLabel: Font { Fonts.sans(TypeSize.base) }
    package static var uiBody: Font { Fonts.sans(TypeSize.base) }
    package static var uiCode: Font { Fonts.mono(TypeSize.base) }
    package static var uiSubtitle: Font { Fonts.sans(TypeSize.strong) }
    // Mismo papel con dos nombres; unificarlos es R-04.
    package static var uiTitle: Font { Fonts.sans(TypeSize.title) }
    /// Hero title: the one place a sheet speaks at display size.
    package static var uiDisplay: Font { Fonts.sans(TypeSize.display) }
    package static var uiHeading: Font { Fonts.sans(TypeSize.title) }
    package static var uiLogo: Font { Fonts.logo(TypeSize.display) }
}

/// The same roles in Geist, for the island, the welcome sheet and the
/// approval panel (16k-2).
package enum GeistFont {
    package static var uiMicro: Font { Fonts.geist(TypeSize.micro) }
    package static var uiCaption: Font { Fonts.geist(TypeSize.micro) }
    package static var uiCta: Font { Fonts.geist(TypeSize.strong) }
    package static var uiLabel: Font { Fonts.geist(TypeSize.base) }
    package static var uiBody: Font { Fonts.geist(TypeSize.base) }
    package static var uiSubtitle: Font { Fonts.geist(TypeSize.strong) }
    package static var uiTitle: Font { Fonts.geist(TypeSize.title) }
    package static var uiDisplay: Font { Fonts.geist(TypeSize.display) }
    package static var uiHeading: Font { Fonts.geist(TypeSize.title) }
}

// Type styling for Views
extension View {
    /// Group header: marks where a section begins without competing with row titles.
    package func typeEyebrow() -> some View {
        font(.uiEyebrow)
            .textCase(.uppercase)
            .tracking(Tracking.wider, at: TypeSize.micro)
            .foregroundStyle(Semantic.mutedForeground)
    }

    /// Large sizes need to close space or they look loose.
    package func typeHeading() -> some View {
        font(.uiHeading).tracking(Tracking.tight, at: TypeSize.title)
    }

    package func typeTitle() -> some View {
        font(.uiTitle).tracking(Tracking.tight, at: TypeSize.title)
    }

    package func typeSubtitle() -> some View {
        font(.uiSubtitle).tracking(Tracking.snug, at: TypeSize.strong)
    }

    /// Letter spacing in em units; SwiftUI wants points.
    package func tracking(_ em: CGFloat, at size: CGFloat) -> some View {
        tracking(em * TypeScale.apply(size))
    }
}
