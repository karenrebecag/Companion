import Foundation
import Testing

package struct ConformanceRule: Decodable {
    package let why: String
    package let pattern: String
}

package struct UIContract: Decodable {
    package let scanDirs: [String]
    package let rules: [String: ConformanceRule]
    package let exemptFiles: [String: String]
    package let baseline: [String: [String: Int]]
}

extension HUDGates {
    /// The gates the wave specs name (12d, 12e); the runner checks presence,
    /// this list checks that none went missing.
    package static let expected = [
        "hold-without-main", "overlay-listens-only", "four-kinds-only",
        "voice-is-a-port-not-a-kind", "stop-is-idle-children-die",
        "cards-are-not-the-conversation", "child-work-has-a-row",
        "no-skill-body-in-hist", "missing-allow-list-denies", "one-host-per-sheet",
        "dictation-never-logged",
    ]
}

package struct HUDGate: Decodable {
    package let id: String
    package let source: String
    package let claim: String
    package let tests: [String]
    package let rules: [String]
}

package struct HUDGates: Decodable {
    package let gates: [HUDGate]
}

package enum Conformance {
    package static func gates(at root: URL) throws -> HUDGates {
        let url = root.appendingPathComponent("conformance/hud-gates.json")
        return try JSONDecoder().decode(HUDGates.self, from: Data(contentsOf: url))
    }

    /// Parents to climb before giving up: deep enough for any Tests/<Target>/
    /// layout, shallow enough that a stray file never resolves to an
    /// unrelated checkout far above it.
    private static let defaultMaxDepth = 8

    /// The marker search without side effects. Split from repoRoot so the depth
    /// bound can be tested without provoking an Issue.
    package static func findRoot(from file: String, maxDepth: Int = defaultMaxDepth) -> URL? {
        var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
        for _ in 0..<maxDepth {
            let hasManifest = FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path)
            let hasContract = FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("conformance/ui-contract.json").path)
            if hasManifest && hasContract { return dir }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// El checkout, buscado por sus marcadores (Package.swift y el contrato) y
    /// no por cuantos niveles hay: el test puede vivir a cualquier profundidad.
    /// Si alguien compila el paquete fuera del repo no hay fuentes que escanear;
    /// se registra un Issue, porque un nil silencioso dejaba a los escaneres
    /// saltarse sin que nadie se enterara.
    package static func repoRoot(from file: String = #filePath) -> URL? {
        if let root = findRoot(from: file) { return root }
        Issue.record("repoRoot: no Package.swift + conformance/ui-contract.json above \(file)")
        return nil
    }

    package static func contract(at root: URL) throws -> UIContract {
        let url = root.appendingPathComponent("conformance/ui-contract.json")
        return try JSONDecoder().decode(UIContract.self, from: Data(contentsOf: url))
    }

    package static func swiftFiles(in dir: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }

    /// Una llamada partida en varias lineas es UNA unidad: si no, `.frame(`
    /// arriba y `width: 16` abajo no matchean ninguna regla y el escaner
    /// reporta limpio un archivo que no lo esta.
    ///
    /// Se descartan las lineas de comentario puro (una regla mencionada en un
    /// comentario no es una infraccion) y las que llevan la valvula
    /// `// token-exempt:`, que es la que ya usa el repo.
    package static func logicalLines(of file: URL) -> [String] {
        guard let src = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return logicalLines(of: src)
    }

    package static func logicalLines(of src: String) -> [String] {
        var out: [String] = []
        var buffer = ""
        var depth = 0
        for raw in src.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if depth == 0, trimmed.hasPrefix("//") { continue }
            buffer += buffer.isEmpty ? line : " " + trimmed
            depth += line.filter { $0 == "(" }.count
            depth -= line.filter { $0 == ")" }.count
            if depth <= 0 {
                if !buffer.contains("token-exempt:") { out.append(buffer) }
                buffer = ""
                depth = 0
            }
        }
        if !buffer.isEmpty, !buffer.contains("token-exempt:") { out.append(buffer) }
        return out
    }

    /// A cited test counts only if it runs: Swift Testing discovers it
    /// (`@Test` on its declaration) or some other line calls it. A name that
    /// is merely declared, or that only a comment mentions, does not.
    package static func testRuns(_ name: String, in lines: [String]) -> Bool {
        let declaration = "func \(name)("
        guard let index = lines.firstIndex(where: { $0.contains(declaration) }) else { return false }
        let attributed = lines[max(0, index - 1)...index].contains { $0.contains("@Test") }
        if attributed { return true }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let call = try? NSRegularExpression(pattern: "(?<!func )\\b\(escaped)\\(") else { return false }
        return lines.contains { line in
            call.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
    }

    package static func count(_ pattern: String, in units: [String]) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return units.reduce(0) { total, unit in
            total + re.numberOfMatches(
                in: unit, range: NSRange(unit.startIndex..., in: unit))
        }
    }
}

extension Conformance {
    package static func keys(in file: URL) -> Set<String> {
        guard let src = try? String(contentsOf: file, encoding: .utf8),
              let re = try? NSRegularExpression(pattern: "^\\s*\"([^\"]+)\"\\s*=",
                                                options: .anchorsMatchLines)
        else { return [] }
        let range = NSRange(src.startIndex..., in: src)
        return Set(re.matches(in: src, range: range).compactMap {
            Range($0.range(at: 1), in: src).map { String(src[$0]) }
        })
    }
}

/// Resolves through the repo markers, so it survives test files moving between folders.
package func repoPath(_ relative: String) -> String {
    (Conformance.repoRoot()?.appendingPathComponent(relative).path) ?? relative
}
