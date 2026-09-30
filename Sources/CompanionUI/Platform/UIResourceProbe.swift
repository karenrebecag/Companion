import AppKit
import CompanionCore
import CoreText
import Foundation

/// CompanionUI's half of the packaging probe (21c): every resource class this
/// module ships, loaded through the same entry points the app uses.
package enum UIResourceProbe {
    /// A key whose English and Spanish values differ, so a missing `es.lproj`
    /// (which falls back to English) cannot pass as Spanish.
    package static let localizedKey = "chat.job.done"
    /// A bundled face no macOS install ships, so resolving it proves the bundle registered.
    package static let fontPostScriptName = "Geist-Regular"

    /// The default is the production resolver, so the packaged app probes the
    /// bundle it will really use.
    package static func checks(bundle: Bundle? = UIResourceBundle.bundle) -> [ResourceProbe.Check] {
        [bundleCheck(bundle)] + localizationChecks(bundle) + [fontCheck(bundle), mascotCheck(bundle)]
    }

    private static func bundleCheck(_ bundle: Bundle?) -> ResourceProbe.Check {
        ResourceProbe.Check(name: "bundle.ui", detail: bundle?.bundleURL.path ?? "missing", passed: bundle != nil)
    }

    private static func localizationChecks(_ bundle: Bundle?) -> [ResourceProbe.Check] {
        let en = Localized.string(localizedKey, language: .en, in: bundle)
        let es = Localized.string(localizedKey, language: .es, in: bundle)
        return [
            ResourceProbe.Check(name: "lproj.en", detail: en, passed: en != localizedKey),
            ResourceProbe.Check(name: "lproj.es", detail: es, passed: es != localizedKey && es != en),
        ]
    }

    private static func fontCheck(_ bundle: Bundle?) -> ResourceProbe.Check {
        guard let fonts = bundle?.resourceURL?.appendingPathComponent("Fonts") else {
            return ResourceProbe.Check(name: "font", detail: "no bundle", passed: false)
        }
        Fonts.register(bundle: bundle)
        let resolves = NSFont(name: fontPostScriptName, size: 12) != nil
        guard resolves, let url = registeredFontURL(fontPostScriptName, under: fonts) else {
            return ResourceProbe.Check(name: "font", detail: "\(fontPostScriptName) not registered from the bundle",
                                       passed: false)
        }
        return ResourceProbe.Check(name: "font", detail: "\(fontPostScriptName) \(url.path)", passed: true)
    }

    private static func mascotCheck(_ bundle: Bundle?) -> ResourceProbe.Check {
        let loaded = ClaudeLogo.load(from: bundle) != nil
        return ResourceProbe.Check(name: "mascot", detail: loaded ? "Mascot/claude.svg" : "not loaded", passed: loaded)
    }

    /// The file in `directory` that holds this PostScript name, if CoreText
    /// has it registered. NSFont alone would also accept a copy the user
    /// installed, which proves nothing about the bundle.
    static func registeredFontURL(_ postScriptName: String, under directory: URL) -> URL? {
        Fonts.fontFiles(in: [directory]).first { url in
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            let holdsName = descriptors.contains {
                CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == postScriptName
            }
            return holdsName && CTFontManagerGetScopeForURL(url as CFURL) != .none
        }
    }
}
