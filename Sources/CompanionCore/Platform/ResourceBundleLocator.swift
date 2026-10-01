import Foundation

/// Where a module's SwiftPM resource bundle was found.
package enum ResourceBundleLocation: Equatable, Sendable {
    /// Open the bundle at this directory.
    case directory(URL)
}

/// The search order behind `UIResourceBundle` and `ServicesResourceBundle`.
///
/// Wave 21c (D5 c): the accessor that native `swift build` generates (Swift
/// 6.3.3) looks at the `.app` ROOT and at the checkout's absolute `.build`
/// path, then calls `fatalError`, which no `do/catch` stops. `bundle.sh`
/// ships the bundles in `Contents/Resources`, where that accessor never
/// looks, so a packaged app on a Mac without this checkout trapped at launch.
/// Same order CodexBar adopted after its 0.48.0 launch crash; see
/// docs/research/recursos-empaquetados-bundle-module.md §4, §7. The accessor
/// is never evaluated: the `.xctest` step covers `swift test` under any
/// scratch path (docs/research/resource-locator-scratch-path.md).
package enum ResourceBundleLocator {
    /// Pure: `isDirectory` is the only contact with the disk.
    package static func locate(
        bundleName: String,
        mainBundleURL: URL,
        executableURL: URL?,
        codeBundleURL: URL?,
        isDirectory: (URL) -> Bool
    ) -> ResourceBundleLocation? {
        if mainBundleURL.pathExtension == "app" {
            let packaged = mainBundleURL.appendingPathComponent("Contents/Resources")
                .appendingPathComponent(bundleName)
            if isDirectory(packaged) { return .directory(packaged) }
        }
        if let executableURL {
            let beside = executableURL.deletingLastPathComponent().appendingPathComponent(bundleName)
            if isDirectory(beside) { return .directory(beside) }
        }
        // SwiftPM writes the resource bundles next to the .xctest in every scratch
        // path, triple and sanitizer measured; a .app's parent would be foreign.
        if let codeBundleURL, codeBundleURL.pathExtension == "xctest" {
            let sibling = codeBundleURL.deletingLastPathComponent().appendingPathComponent(bundleName)
            if isDirectory(sibling) { return .directory(sibling) }
        }
        return nil
    }

    package static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && directory.boolValue
    }

    /// The bundle that holds this module's code: the `.xctest` under
    /// `swift test`, the `.app` when packaged. `Bundle.main` is the toolchain's
    /// runner under test, so only a class defined here points at the real build.
    package static let defaultCodeBundleURL: URL = Bundle(for: CodeBundleAnchor.self).bundleURL
}

private final class CodeBundleAnchor {}
