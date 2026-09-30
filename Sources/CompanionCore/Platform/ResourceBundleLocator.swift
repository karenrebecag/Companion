import Foundation

/// Where a module's SwiftPM resource bundle was found.
package enum ResourceBundleLocation: Equatable, Sendable {
    /// Open the bundle at this directory.
    case directory(URL)
    /// Only the generated `Bundle.module` knows the path, and its build-path
    /// candidate was seen on disk, so evaluating it cannot trap.
    case swiftPMModule
}

/// The search order behind `UIResourceBundle` and `ServicesResourceBundle`.
///
/// Wave 21c (D5 c): the accessor that native `swift build` generates (Swift
/// 6.3.3) looks at the `.app` ROOT and at the checkout's absolute `.build`
/// path, then calls `fatalError`, which no `do/catch` stops. `bundle.sh`
/// ships the bundles in `Contents/Resources`, where that accessor never
/// looks, so a packaged app on a Mac without this checkout trapped at launch.
/// Same order CodexBar adopted after its 0.48.0 launch crash; see
/// docs/research/recursos-empaquetados-bundle-module.md §4, §7.
package enum ResourceBundleLocator {
    /// Pure: `isDirectory` is the only contact with the disk.
    package static func locate(
        bundleName: String,
        mainBundleURL: URL,
        executableURL: URL?,
        buildDirectory: URL?,
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
        if let buildDirectory, isDirectory(buildDirectory.appendingPathComponent(bundleName)) {
            return .swiftPMModule
        }
        return nil
    }

    package static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && directory.boolValue
    }

    /// The directory the generated accessor falls back to: `.build/<config>`
    /// of the checkout this file was compiled from (a symlink to the
    /// triple-specific folder). Absent on any other Mac, which is the point.
    /// HACK: assumes the default scratch path and no `--triple`. A build with
    /// `--scratch-path` finds nothing here and degrades to nil (never a trap);
    /// derive it from the build instead if such a build ever needs resources.
    package static let defaultBuildDirectory: URL = {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Platform
            .deletingLastPathComponent() // CompanionCore
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent()
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        return packageRoot.appendingPathComponent(".build/\(configuration)", isDirectory: true)
    }()
}
