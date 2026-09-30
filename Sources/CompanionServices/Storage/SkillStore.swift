import CompanionCore
import Foundation

/// One system skill as it ships inside the app: the folder name and the
/// text of its `SKILL.md`. Seeded onto disk so the user can open it and the
/// specialist can read_file it, like everything else Companion remembers.
package struct BundledSkill: Sendable, Equatable {
    package var name: String
    package var content: String

    package init(name: String, content: String) {
        self.name = name
        self.content = content
    }
}

package enum SkillStoreError: Error, Sendable, Equatable {
    case bundleMissing
    case unreadable(String)
}

package enum BundledSkills {
    /// `Skills/<name>/SKILL.md` inside this module's resource bundle.
    package static func load() throws -> [BundledSkill] {
        try load(from: ServicesResourceBundle.bundle)
    }

    /// A nil bundle (not found, 21c) throws `bundleMissing`, which the
    /// launch's do/catch already turns into "no system skills".
    package static func load(from bundle: Bundle?) throws -> [BundledSkill] {
        guard let root = bundle?.url(forResource: "Skills", withExtension: nil) else {
            throw SkillStoreError.bundleMissing
        }
        let folders: [URL]
        do {
            folders = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            throw SkillStoreError.unreadable(root.path)
        }
        var skills: [BundledSkill] = []
        for folder in folders {
            let file = folder.appendingPathComponent(SkillKind.skill.fileName)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                let content = try String(contentsOf: file, encoding: .utf8)
                skills.append(BundledSkill(name: folder.lastPathComponent, content: content))
            } catch {
                throw SkillStoreError.unreadable(file.path)
            }
        }
        return skills.sorted { $0.name < $1.name }
    }
}

/// The three folders as one catalog (Wave 11a): `skills/default/` seeded
/// from the bundle and owned by the app, `skills/custom/` and `knowledge/`
/// owned by the user. Scanned per read — a handful of small files — so a
/// skill saved in this turn is in the catalog on the next.
/// HACK: no cache. Index by modification date when a catalog of hundreds
/// makes the scan show up in a turn's latency.
package final class SkillStore: SkillReading, @unchecked Sendable {
    private let location: SkillsLocation
    private let bundled: [BundledSkill]
    private let lock = NSLock()
    /// Files already reported as invalid, so the log says it once.
    private var warned: Set<String> = []

    package init(location: SkillsLocation, bundled: [BundledSkill]) {
        self.location = location
        self.bundled = bundled
    }

    /// Writes every bundled skill whose text on disk differs, including one
    /// edited by hand: `default/` is the system's copy, `custom/` is the
    /// user's. Returns the names written.
    @discardableResult
    package func seed() -> [String] {
        var written: [String] = []
        for skill in bundled {
            let folder = location.systemSkills.appendingPathComponent(skill.name, isDirectory: true)
            let file = folder.appendingPathComponent(SkillKind.skill.fileName)
            if let existing = read(file), existing == skill.content { continue }
            do {
                // 0700/0600 like the attachments folder: what the user can
                // open is the user's, not the Mac's other accounts'.
                try FileManager.default.createDirectory(
                    at: folder, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                try skill.content.write(to: file, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: file.path)
                written.append(skill.name)
            } catch {
                Log.app("skills: could not seed \(skill.name) (\(error))")
            }
        }
        return written
    }

    package func catalog() -> [SkillCard] { scan() }

    /// A missing folder is the normal empty state. A file that does not parse
    /// is skipped and logged once. A name in both `default/` and `custom/`
    /// keeps the system one: a collision is the user's to fix, not the
    /// model's to disambiguate.
    package func scan() -> [SkillCard] {
        var cards: [SkillCard] = []
        var seen: Set<String> = []
        for (base, kind, origin) in [
            (location.systemSkills, SkillKind.skill, SkillOrigin.system),
            (location.customSkills, .skill, .custom),
            (location.knowledge, .knowledge, .custom),
        ] {
            for folder in subfolders(of: base) {
                let file = folder.appendingPathComponent(kind.fileName)
                guard let text = read(file) else { continue }
                let name = folder.lastPathComponent
                do {
                    let fm = try SkillFrontmatter.parse(text, folder: name)
                    let key = "\(kind.rawValue):\(fm.name)"
                    guard seen.insert(key).inserted else {
                        warnOnce(file.path, "skills: \(file.path) hides behind the system skill of the same name")
                        continue
                    }
                    cards.append(SkillCard(
                        name: fm.name, description: fm.description, path: file.path,
                        kind: kind, origin: origin, allowedTools: fm.allowedTools))
                } catch {
                    warnOnce(file.path, "skills: skipping \(file.path): \(error.why)")
                }
            }
        }
        return cards
    }

    package func body(named name: String) -> String? {
        guard SkillFrontmatter.isValidName(name) else { return nil }
        guard let card = scan().first(where: { $0.name == name }) else { return nil }
        guard let text = read(URL(fileURLWithPath: card.path)) else { return nil }
        do {
            return try SkillFrontmatter.parse(text, folder: name).body
        } catch {
            return nil
        }
    }

    package func rendered(language: AppLanguage) -> String {
        SkillCatalog.render(scan(), language: language)
    }

    // MARK: - private

    private func subfolders(of base: URL) -> [URL] {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            return []
        }
        return entries.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// nil when the file is absent, over the size cap or not UTF-8: all mean
    /// "not a skill". The size is checked before the read: this runs every
    /// turn, and one huge file must not be reloaded on each (security review).
    private func read(_ file: URL) -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
            guard size <= SkillCatalog.Caps.fileBytes else {
                warnOnce(file.path, "skills: skipping \(file.path): \(size) bytes, over the cap")
                return nil
            }
            return try String(contentsOf: file, encoding: .utf8)
        } catch {
            warnOnce(file.path, "skills: cannot read \(file.path) (\(error))")
            return nil
        }
    }

    private func warnOnce(_ key: String, _ message: String) {
        lock.lock()
        let first = warned.insert(key).inserted
        lock.unlock()
        if first { Log.app(message) }
    }
}
