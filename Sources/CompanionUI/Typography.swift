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
            NotificationCenter.default.post(
                name: .companionChromeDidChange, object: nil)
        }
    }

    public static let floor: CGFloat = 12

    public static func apply(_ size: CGFloat) -> CGFloat {
        Swift.max(Self.floor, size + CGFloat(origin + delta))
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
