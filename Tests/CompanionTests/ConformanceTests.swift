import Foundation
import Testing

// Conformance de la reticula de CompanionUI. Las reglas y sus valores viven en
// conformance/ui-contract.json; este runner es deliberadamente tonto. Patron
// tomado de ATOMUIKIT (modelo Willison: el contrato es data, no un parrafo en
// CLAUDE.md que un agente puede ignorar sin que nada falle).
//
// Ratchet, no big-bang: el baseline registra la deuda por archivo, asi que el
// gate se enciende HOY sin fingir que el pasado es perfecto y congela la
// entrada de deuda nueva.

struct ConformanceRule: Decodable {
    let why: String
    let pattern: String
}

struct UIContract: Decodable {
    let scanDirs: [String]
    let rules: [String: ConformanceRule]
    let exemptFiles: [String: String]
    let baseline: [String: [String: Int]]
}

@Test func uiConformanceTests() throws {
    guard let root = Conformance.repoRoot() else {
        print("  nota  [conformance] fuera del checkout: no hay que escanear")
        return
    }
    let contract = try Conformance.contract(at: root)
    var clean = 0

    for dir in contract.scanDirs {
        let base = root.appendingPathComponent(dir)
        for file in Conformance.swiftFiles(in: base).sorted(by: { $0.path < $1.path }) {
            // Ruta relativa al scanDir, no el basename: la clave del baseline
            // tiene que decir de que archivo habla sin ambiguedad.
            let rel = file.path.replacingOccurrences(
                of: base.path + "/", with: "")
            if contract.exemptFiles[rel] != nil { continue }
            let units = Conformance.logicalLines(of: file)
            let allowed = contract.baseline[rel] ?? [:]
            var dirty = false

            for name in contract.rules.keys.sorted() {
                let rule = contract.rules[name]!
                let hits = Conformance.count(rule.pattern, in: units)
                let budget = allowed[name] ?? 0
                if hits > budget {
                    dirty = true
                    expect(
                        false,
                        "conformance: \(rel) — \(name) \(hits) > baseline "
                            + "\(budget). \(rule.why)")
                } else if hits < budget {
                    print("  nota  [conformance] \(rel): \(name) bajo a "
                        + "\(hits) (baseline \(budget)) — baja el baseline en "
                        + "conformance/ui-contract.json")
                }
            }
            if !dirty { clean += 1 }
        }
    }
    print("  ok    [conformance] \(clean) archivos dentro de contrato")
}

/// 16p-2: `system-font` solo ve el literal; un tamaño calculado
/// (`.system(size: X * 0.8)`) esquivaba igual TypeScale y la fuente del
/// usuario. La regla nueva tiene que ver esas formas y ninguna otra.
@Test func systemFontExpressionRuleTests() throws {
    guard let root = Conformance.repoRoot() else { return }
    let contract = try Conformance.contract(at: root)
    guard let rule = contract.rules["system-font-expression"] else {
        expect(false, "contrato: falta la regla system-font-expression")
        return
    }
    let leaks = Conformance.logicalLines(of: """
        .font(.system(size: SidebarMetrics.icon * 0.85))
        .font(Font.system(size: TypeSize.body, weight: .semibold))
        .font(.system(
            size: IconSize.hero, weight: .light))
        """)
    expectEq(Conformance.count(rule.pattern, in: leaks), 3,
             "system-font-expression: salta con un tamaño calculado, también partido en líneas")
    let clean = Conformance.logicalLines(of: """
        .font(Fonts.sans(TypeSize.body))
        .font(.system(size: 12))
        Image(systemName: "xmark")
        .font(GeistFont.uiCaption)
        """)
    expectEq(Conformance.count(rule.pattern, in: clean), 0,
             "system-font-expression: no salta con Fonts ni con el literal (ese es de system-font)")
}

/// El libro de puertas del HUD (Wave 12d). No ejecuta nada: comprueba que
/// cada puerta cita tests que existen y corren (`@Test` o invocados) y
/// reglas que existen, para que el libro no pueda citar pruebas que ya se
/// borraron o que nadie llama.
@Test func hudGatesTests() throws {
    guard let root = Conformance.repoRoot() else { return }
    let ledger = try Conformance.gates(at: root)
    let contract = try Conformance.contract(at: root)
    let testSources = Conformance.swiftFiles(
        in: root.appendingPathComponent("Tests"))
    let corpus = testSources.flatMap { Conformance.logicalLines(of: $0) }
    expect(!ledger.gates.isEmpty, "puertas: el libro no está vacío")
    for gate in ledger.gates {
        expect(!gate.tests.isEmpty || !gate.rules.isEmpty,
               "puertas: \(gate.id) no cita ni tests ni reglas")
        for name in gate.tests {
            expect(Conformance.testRuns(name, in: corpus),
                   "puertas: \(gate.id) cita un test que no existe o no corre: \(name)")
        }
        for rule in gate.rules {
            expect(contract.rules[rule] != nil,
                   "puertas: \(gate.id) cita una regla que no existe: \(rule)")
        }
    }
    print("  ok    [puertas] \(ledger.gates.count) puertas del HUD con pruebas")
}

extension HUDGates {
    /// The gates the wave specs name (12d, 12e); the runner checks presence,
    /// this list checks that none went missing.
    static let expected = [
        "hold-without-main", "overlay-listens-only", "four-kinds-only",
        "voice-is-a-port-not-a-kind", "stop-is-idle-children-die",
        "cards-are-not-the-conversation", "child-work-has-a-row",
        "no-skill-body-in-hist", "missing-allow-list-denies", "one-host-per-sheet",
        "dictation-never-logged",
    ]
}

struct HUDGate: Decodable {
    let id: String
    let source: String
    let claim: String
    let tests: [String]
    let rules: [String]
}

struct HUDGates: Decodable {
    let gates: [HUDGate]
}

enum Conformance {
    static func gates(at root: URL) throws -> HUDGates {
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

    static func contract(at root: URL) throws -> UIContract {
        let url = root.appendingPathComponent("conformance/ui-contract.json")
        return try JSONDecoder().decode(UIContract.self, from: Data(contentsOf: url))
    }

    static func swiftFiles(in dir: URL) -> [URL] {
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
    static func logicalLines(of file: URL) -> [String] {
        guard let src = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return logicalLines(of: src)
    }

    static func logicalLines(of src: String) -> [String] {
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
    static func testRuns(_ name: String, in lines: [String]) -> Bool {
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

    static func count(_ pattern: String, in units: [String]) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return units.reduce(0) { total, unit in
            total + re.numberOfMatches(
                in: unit, range: NSRange(unit.startIndex..., in: unit))
        }
    }
}

// MARK: - Paridad del catalogo

/// Complemento de la regla `copy-literal`: esa empuja el copy HACIA el
/// catalogo, y sin esto se puede mover una cadena y publicar el idioma que
/// falta en silencio — la UI cae al identificador crudo delante del usuario.
@Test func catalogParityTests() throws {
    guard let root = Conformance.repoRoot() else {
        print("  nota  [catalogo] fuera del checkout")
        return
    }
    let base = root.appendingPathComponent("Sources/CompanionUI")
    let en = Conformance.keys(in: base.appendingPathComponent("en.lproj/Localizable.strings"))
    let es = Conformance.keys(in: base.appendingPathComponent("es.lproj/Localizable.strings"))

    expect(!en.isEmpty, "catalogo: en.lproj no se pudo leer")
    for missing in es.subtracting(en).sorted() {
        expect(false, "catalogo: \(missing) esta en es y falta en en")
    }
    for missing in en.subtracting(es).sorted() {
        expect(false, "catalogo: \(missing) esta en en y falta en es")
    }
    print("  ok    [catalogo] \(en.count) claves en los dos idiomas")
}

extension Conformance {
    static func keys(in file: URL) -> Set<String> {
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

// MARK: - repoRoot(from:)

/// Test folders will live at different depths; the root is found by its
/// markers, never by counting path components.
@Test func repoRootFindsRootFromDeeperPaths() throws {
    let root = try scriptTempRoot("repo-root")
    defer { removeScriptTemp(root) }
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("conformance"), withIntermediateDirectories: true)
    try "".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    try "{}".write(
        to: root.appendingPathComponent("conformance/ui-contract.json"), atomically: true, encoding: .utf8)

    expectEq(Conformance.repoRoot(from: root.path + "/Tests/A/B/x.swift")?.path, root.path,
             "repoRoot: depth 3 below the root")
    expectEq(Conformance.repoRoot(from: root.path + "/Tests/x.swift")?.path, root.path,
             "repoRoot: depth 1 below the root")
    expectEq(Conformance.findRoot(from: root.path + "/a/b/c/d/e/f/g/x.swift")?.path, root.path,
             "findRoot: eight directories up still finds it")
    expect(Conformance.findRoot(from: root.path + "/a/b/c/d/e/f/g/h/x.swift") == nil,
           "findRoot: nine directories up is past the walk limit")
    expectEq(Conformance.findRoot(from: root.path + "/a/b/c/d/e/f/g/h/x.swift", maxDepth: 9)?.path, root.path,
             "findRoot: the bound is the parameter")
}

@Test func repoRootFromThisFileIsTheCheckout() {
    let root = Conformance.repoRoot()
    expect(root != nil, "repoRoot: the default #filePath resolves inside the checkout")
    expect(FileManager.default.fileExists(atPath: (root?.path ?? "") + "/Package.swift"),
           "repoRoot: the result holds Package.swift")
}

/// A silent nil let the scanners skip themselves; the miss must be loud.
@Test func repoRootRecordsAnIssueWhenNothingIsFound() {
    withKnownIssue {
        let root = Conformance.repoRoot(from: "/tmp/x/y.swift")
        expect(root == nil, "repoRoot: no markers means nil")
    } matching: { issue in
        issue.comments.contains { $0.rawValue.contains("repoRoot") }
    }
}

@Test func findRootNeverRecords() {
    expect(Conformance.findRoot(from: "/tmp/x/y.swift") == nil, "findRoot: a miss is a plain nil")
}
