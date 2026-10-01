import CompanionCore
import Foundation
import os

/// CompanionUI's resource bundle (fonts, mascot, `.lproj`), or nil. Never
/// evaluate `Bundle.module`: its generated accessor traps when the
/// bundle is missing (`ResourceBundleLocator` says why).
nonisolated enum UIResourceBundle {
    /// SE-0271 calls the name implementation-defined; 21c's packaging probe
    /// is what catches a toolchain that renames it.
    static let name = "Companion_CompanionUI.bundle"

    // UI does not reach Services' Log; the message never names a path.
    private static let log = Logger(subsystem: "com.karen.companion", category: "resources")

    /// Resolved once, so a missing bundle is logged once.
    static let bundle: Bundle? = {
        let resolved = resolve()
        if resolved == nil {
            log.error("resources: CompanionUI bundle not found; system fonts, raw copy keys, no mascot")
        }
        return resolved
    }()

    static func resolve(
        mainBundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL,
        codeBundleURL: URL? = ResourceBundleLocator.defaultCodeBundleURL
    ) -> Bundle? {
        switch ResourceBundleLocator.locate(
            bundleName: name, mainBundleURL: mainBundleURL, executableURL: executableURL,
            codeBundleURL: codeBundleURL, isDirectory: ResourceBundleLocator.isDirectory)
        {
        case let .directory(url): Bundle(url: url)
        case nil: nil
        }
    }
}
