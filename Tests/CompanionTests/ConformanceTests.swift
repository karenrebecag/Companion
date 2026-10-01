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
