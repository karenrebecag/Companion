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

/// El libro de puertas del HUD (Wave 12d). No ejecuta nada: comprueba que
/// cada puerta cita tests que existen y corren (`@Test` o invocados) y
/// reglas que existen, para que el libro no pueda citar pruebas que ya se
/// borraron o que nadie llama.
@Test func hudGatesTests() throws {
    guard let root = Conformance.repoRoot() else { return }
    let ledger = try Conformance.gates(at: root)
    let contract = try Conformance.contract(at: root)
    let testSources = Conformance.swiftFiles(
        in: root.appendingPathComponent("Tests/CompanionTests"))
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

    /// El checkout, desde este archivo. Si alguien compila el paquete fuera del
    /// repo no hay fuentes que escanear y el test se salta en vez de mentir.
    static func repoRoot() -> URL? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CompanionTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // raiz
        let contract = here.appendingPathComponent("conformance/ui-contract.json")
        return FileManager.default.fileExists(atPath: contract.path) ? here : nil
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
