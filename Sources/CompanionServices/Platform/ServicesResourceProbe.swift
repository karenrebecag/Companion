import CompanionCore
import Foundation

/// CompanionServices' half of the packaging probe (21c): the system skills,
/// the vendored Mermaid, and the browser extension the app ships next to them.
@MainActor
package enum ServicesResourceProbe {
    /// The defaults are what the app uses: the production resolver and the
    /// app's own `Contents/Resources` for the extension (D9).
    package static func checks(
        bundle: Bundle? = ServicesResourceBundle.bundle,
        mainResourceURL: URL? = Bundle.main.resourceURL
    ) -> [ResourceProbe.Check] {
        [
            ResourceProbe.Check(name: "bundle.services", detail: bundle?.bundleURL.path ?? "missing",
                                passed: bundle != nil),
            skillsCheck(bundle),
            mermaidCheck(bundle),
            ResourceProbe.browserExtension(resourceURL: mainResourceURL),
        ]
    }

    /// The loader's count against a plain `Skills/*/SKILL.md` glob of the same
    /// folder: a loader that silently skipped a skill would disagree.
    private static func skillsCheck(_ bundle: Bundle?) -> ResourceProbe.Check {
        let loaded: [BundledSkill]
        do {
            loaded = try BundledSkills.load(from: bundle)
        } catch {
            return ResourceProbe.Check(name: "skills", detail: "load failed: \(error)", passed: false)
        }
        let onDisk = skillFileCount(in: bundle?.url(forResource: "Skills", withExtension: nil))
        let passed = !loaded.isEmpty && loaded.count == onDisk
        return ResourceProbe.Check(name: "skills", detail: passed ? "\(loaded.count)" : "loaded \(loaded.count), on disk \(onDisk)",
                                   passed: passed)
    }

    private static func skillFileCount(in root: URL?) -> Int {
        guard let root else { return 0 }
        let folders: [URL]
        do {
            folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch {
            return 0
        }
        return folders.filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(SkillKind.skill.fileName).path)
        }.count
    }

    /// `vendoredScript(from:)` returns nil unless the SHA-256 matches the pin.
    private static func mermaidCheck(_ bundle: Bundle?) -> ResourceProbe.Check {
        let verified = WebKitDiagramRenderer.vendoredScript(from: bundle) != nil
        return ResourceProbe.Check(name: "mermaid", detail: verified ? "sha256 verified" : "missing or unverified",
                                   passed: verified)
    }
}
