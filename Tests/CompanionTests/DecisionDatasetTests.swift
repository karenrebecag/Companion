import Foundation
import Testing

// Wave DM0. Validation and coverage metrics for the decision-model dataset.
// Reads ordenes.jsonl, validates schema, and enforces minimum coverage:
// ≥150 rows, ≥60% real, ≥5 per action, both languages.

@Test @MainActor func decisionDatasetTests() throws {
    try testCadaLineaParsea()
    try testSchemaYVocabulario()
    testMinimosDelConjunto()
}

// MARK: - Private Types

private struct Orden: Decodable {
    let id: String
    let texto: String
    let idioma: String
    let accion: String
    let args: [String: AnyCodable]
    let irreversible: Bool
    let fuente: String
    let notas: String

    enum CodingKeys: String, CodingKey {
        case id, texto, idioma, accion, args, irreversible, fuente, notas
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        texto = try container.decode(String.self, forKey: .texto)
        idioma = try container.decode(String.self, forKey: .idioma)
        accion = try container.decode(String.self, forKey: .accion)
        irreversible = try container.decode(Bool.self, forKey: .irreversible)
        fuente = try container.decode(String.self, forKey: .fuente)
        notas = try container.decode(String.self, forKey: .notas)

        // Decode args as [String: AnyCodable], which handles arbitrary JSON values
        let argsData = try container.decode([String: AnyCodable].self, forKey: .args)
        args = argsData
    }
}

private enum AnyCodable: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "unsupported type in args")
        }
    }
}

// MARK: - Loader

private func loadOrdenes() throws -> [Orden] {
    let here = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // CompanionTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
    let path = here.appendingPathComponent("docs/research/decision-model/dataset/ordenes.jsonl")
    let content = try String(contentsOf: path, encoding: .utf8)
    let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
    var ordenes: [Orden] = []

    for (index, line) in lines.enumerated() {
        let lineNum = index + 1
        let decoder = JSONDecoder()
        do {
            let orden = try decoder.decode(Orden.self, from: Data(line.utf8))
            ordenes.append(orden)
        } catch {
            throw TestError.parseError(line: lineNum, reason: error.localizedDescription)
        }
    }
    return ordenes
}

private enum TestError: Error, CustomStringConvertible {
    case parseError(line: Int, reason: String)
    case schemaError(reason: String)

    var description: String {
        switch self {
        case .parseError(let line, let reason):
            return "Line \(line): \(reason)"
        case .schemaError(let reason):
            return reason
        }
    }
}

// MARK: - Test 5: Each line parses to schema

private func testCadaLineaParsea() throws {
    let ordenes = try loadOrdenes()
    expect(!ordenes.isEmpty, "dataset: conjunto vacio")
}

// MARK: - Test 6: Schema and vocabulary validation

private func testSchemaYVocabulario() throws {
    let ordenes = try loadOrdenes()

    // Allowed actions with their exact args keys
    let allowedActions: [String: Set<String>] = [
        "open_app": ["app"],
        "open_url": ["url"],
        "open_file": ["path"],
        "list_apps": [],
        "read_skill": ["name"],
        "find_places": ["query"],
        "volume": ["op"],
        "shortcut": ["shortcut"],
        "scroll": ["direction", "amount"],
        "media": ["op"],
        "system": ["op"],
        "type_text": ["text", "submit"],
        "task": ["goal"],
        "none": [],
    ]

    // Enum values for specific actions
    let volumeOps = Set(["up", "down", "mute", "unmute", "max"])
    let shortcuts = Set([
        "enter", "escape", "copy", "paste", "undo", "redo", "select_all", "save",
        "find", "new_tab", "close_tab_or_window", "reopen_closed_tab", "quit_app",
        "reload", "browser_back", "next_tab", "previous_tab", "fullscreen", "zoom_in",
        "zoom_out", "send_message",
    ])
    let scrollDirections = Set(["up", "down", "top", "bottom"])
    let scrollAmounts = Set(["line", "page", "lots"])
    let mediaOps = Set(["play", "pause", "next", "previous"])
    let systemOps = Set(["lock", "sleep_display", "show_desktop", "toggle_dark_mode", "empty_trash", "screenshot"])

    // Track for uniqueness and counts
    var seenIds = Set<String>()
    var countPerAccion: [String: Int] = [:]
    var countPerFuente: [String: Int] = [:]
    var hasEs = false
    var hasEn = false

    for orden in ordenes {
        // Test id uniqueness
        if seenIds.contains(orden.id) {
            throw TestError.schemaError(reason: "id duplicado: \(orden.id)")
        }
        seenIds.insert(orden.id)

        // Test id prefix matches fuente
        let prefix = String(orden.id.prefix(1))
        let expected = orden.fuente == "real" ? "r" : "s"
        if prefix != expected {
            throw TestError.schemaError(
                reason: "id \(orden.id): prefix debe ser \(expected) para fuente=\(orden.fuente)")
        }

        // Test idioma is valid
        if !["es", "en"].contains(orden.idioma) {
            throw TestError.schemaError(reason: "id \(orden.id): idioma invalido: \(orden.idioma)")
        }
        if orden.idioma == "es" { hasEs = true }
        if orden.idioma == "en" { hasEn = true }

        // Test fuente is valid
        if !["real", "sintetica"].contains(orden.fuente) {
            throw TestError.schemaError(reason: "id \(orden.id): fuente invalida: \(orden.fuente)")
        }
        countPerFuente[orden.fuente, default: 0] += 1

        // Test accion is valid
        guard let allowedKeys = allowedActions[orden.accion] else {
            throw TestError.schemaError(reason: "id \(orden.id): accion invalida: \(orden.accion)")
        }

        // Test args keys are exactly as expected (no extra, no missing)
        let argsKeys = Set(orden.args.keys)
        if argsKeys != allowedKeys {
            throw TestError.schemaError(
                reason: "id \(orden.id): args keys invalidas. accion=\(orden.accion), esperado=\(allowedKeys), obtenido=\(argsKeys)")
        }

        // Validate enum values for specific actions
        if orden.accion == "volume", let opVal = orden.args["op"]?.stringValue {
            if !volumeOps.contains(opVal) {
                throw TestError.schemaError(
                    reason: "id \(orden.id): volume op invalido: \(opVal)")
            }
        }

        if orden.accion == "shortcut", let shortcutVal = orden.args["shortcut"]?.stringValue {
            if !shortcuts.contains(shortcutVal) {
                throw TestError.schemaError(
                    reason: "id \(orden.id): shortcut invalido: \(shortcutVal)")
            }
        }

        if orden.accion == "scroll" {
            if let dirVal = orden.args["direction"]?.stringValue {
                if !scrollDirections.contains(dirVal) {
                    throw TestError.schemaError(
                        reason: "id \(orden.id): scroll direction invalido: \(dirVal)")
                }
            }
            if let amtVal = orden.args["amount"]?.stringValue {
                if !scrollAmounts.contains(amtVal) {
                    throw TestError.schemaError(
                        reason: "id \(orden.id): scroll amount invalido: \(amtVal)")
                }
            }
        }

        if orden.accion == "media", let opVal = orden.args["op"]?.stringValue {
            if !mediaOps.contains(opVal) {
                throw TestError.schemaError(
                    reason: "id \(orden.id): media op invalido: \(opVal)")
            }
        }

        if orden.accion == "system", let opVal = orden.args["op"]?.stringValue {
            if !systemOps.contains(opVal) {
                throw TestError.schemaError(
                    reason: "id \(orden.id): system op invalido: \(opVal)")
            }
        }

        // Test irreversible flag rules
        let irreversibleShortcuts: Set<String> = ["enter", "quit_app", "send_message"]
        let irreversibleAllowed =
            (orden.accion == "system" && orden.args["op"]?.stringValue == "empty_trash") ||
            (orden.accion == "shortcut"
                && irreversibleShortcuts.contains(orden.args["shortcut"]?.stringValue ?? "")) ||
            (orden.accion == "type_text" && orden.args["submit"]?.boolValue == true) ||
            (orden.accion == "task")  // tasks can be reversible or irreversible

        if orden.irreversible && !irreversibleAllowed {
            throw TestError.schemaError(
                reason: "id \(orden.id): irreversible=true no permitido para esta accion")
        }

        // Un task es irreversible si alguno de sus pasos EMPIEZA por un verbo
        // que envía, borra, paga o cierra sesión. Solo el verbo que encabeza
        // cada paso decide: "write buy milk" dicta una nota, no compra nada
        // (falso positivo del review 2026-09-22).
        if orden.accion == "task", let goal = orden.args["goal"]?.stringValue?.lowercased() {
            let stems = ["envi", "mand", "borr", "elimin", "pag", "compr", "vaci", "cierra sesi",
                         "send", "delete", "remove", "pay", "buy", "purchase", "empty", "log out", "sign out"]
            let steps = goal.replacingOccurrences(of: " y ", with: " and ")
                .components(separatedBy: " and ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let destructive = steps.contains { step in stems.contains { step.hasPrefix($0) } }
            if destructive != orden.irreversible {
                throw TestError.schemaError(
                    reason: "id \(orden.id): task '\(goal)' debe llevar irreversible=\(destructive)")
            }
        }

        countPerAccion[orden.accion, default: 0] += 1
    }

    // Verify both languages present
    expect(hasEs, "schema: idioma 'es' debe estar presente")
    expect(hasEn, "schema: idioma 'en' debe estar presente")

    // Verify no action has zero rows (enforced by loading and not empty check)
    for action in allowedActions.keys {
        expect(countPerAccion[action] != nil || action == "none",
               "schema: accion \(action) sin filas")
    }
}

// MARK: - Test 7: Minimum coverage (wrapped in withKnownIssue)

private func testMinimosDelConjunto() {
    withKnownIssue(
        "DM0: el conjunto no está completo hasta que Karen reclasifique las órdenes reales"
    ) {
        do {
            let ordenes = try loadOrdenes()

            // Count per action
            var countPerAccion: [String: Int] = [:]
            var realCount = 0

            for orden in ordenes {
                countPerAccion[orden.accion, default: 0] += 1
                if orden.fuente == "real" {
                    realCount += 1
                }
            }

            let totalCount = ordenes.count
            let realShare = totalCount > 0 ? Double(realCount) / Double(totalCount) : 0

            // Assertion 1: ≥150 rows
            expect(
                totalCount >= 150,
                "minimos: ≥150 filas (actual: \(totalCount))")

            // Assertion 2: ≥60% real
            expect(
                realShare >= 0.60,
                "minimos: ≥60% real (actual: \(Int(realShare * 100))%, \(realCount)/\(totalCount))")

            // Assertion 3: ≥5 per action
            for (action, count) in countPerAccion.sorted(by: { $0.key < $1.key }) {
                expect(
                    count >= 5,
                    "minimos: accion '\(action)' debe tener ≥5 filas (actual: \(count))")
            }
        } catch {
            expect(false, "minimos: error cargando dataset: \(error)")
        }
    }
}

// MARK: - Helper Extension

private extension AnyCodable {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}
