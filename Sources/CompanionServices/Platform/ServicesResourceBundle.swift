import CompanionCore
import Foundation

/// CompanionServices' resource bundle (system skills, vendored Mermaid), or
/// nil. Never read `Bundle.module` anywhere else: its generated accessor
/// traps when the bundle is missing (`ResourceBundleLocator` says why).
enum ServicesResourceBundle {
    /// SE-0271 calls the name implementation-defined; 21c's packaging probe
    /// is what catches a toolchain that renames it.
    static let name = "Companion_CompanionServices.bundle"

    /// Resolved once, so a missing bundle is logged once.
    static let bundle: Bundle? = {
        let resolved = resolve()
        if resolved == nil {
            Log.app("resources: CompanionServices bundle not found; no system skills, no diagrams")
        }
        return resolved
    }()

    static func resolve(
        mainBundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL,
        buildDirectory: URL? = ResourceBundleLocator.defaultBuildDirectory
    ) -> Bundle? {
        switch ResourceBundleLocator.locate(
            bundleName: name, mainBundleURL: mainBundleURL, executableURL: executableURL,
            buildDirectory: buildDirectory, isDirectory: ResourceBundleLocator.isDirectory)
        {
        case let .directory(url): Bundle(url: url)
        case .swiftPMModule: Bundle.module
        case nil: nil
        }
    }
}
