@testable import CompanionCore
import Foundation
import Testing

// 16q-3a: the research corpus the judge is measured against.

private struct CorpusCase {
    let id: String, lang: String, category: String
    let expected: [Bool]
    let actionCount: Int
    let planted: String?
    let words: String
    let tags: Set<String>
    let hasMCP: Bool
}

private let corpusCategories: Set<String> = [
    "injection", "other_yes", "other_target", "broader_effect", "legit", "mixed_batch", "language",
]
/// Over the batch cap on purpose: the adapter answers `failed:too_many` for these.
private let tooManyCategory = "too_many"
private let requiredTags: Set<String> = [
    "swapped_target", "planted_in_args", "plausible_planted", "homoglyph", "no_antecedent", "negation",
    "truncated_words", "batch_8", "batch_9", "mcp", "multi_action",
]

private func loadCorpus() throws -> [CorpusCase] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("docs/research/action-judge/corpus.jsonl")
    let content = try String(contentsOf: url, encoding: .utf8)
    return try content.split(separator: "\n", omittingEmptySubsequences: true).map { line in
        guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let id = object["id"] as? String, let lang = object["lang"] as? String,
              let category = object["category"] as? String, let words = object["words"] as? String,
              let actions = object["actions"] as? [[String: Any]], let expected = object["expected"] as? [Bool],
              object["notes"] is String
        else { throw CorpusError("fila ilegible: \(line.prefix(60))") }
        expect(!words.isEmpty, "16q-3a corpus \(id): words no vacio")
        for action in actions { try checkAction(action, id: id) }
        let hasMCP = actions.contains { !((($0["tool"] as? String) ?? "").hasPrefix("app:")) }
        return CorpusCase(id: id, lang: lang, category: category, expected: expected,
                          actionCount: actions.count, planted: object["planted"] as? String,
                          words: words, tags: Set(object["tags"] as? [String] ?? []), hasMCP: hasMCP)
    }
}

private struct CorpusError: Error { let message: String; init(_ message: String) { self.message = message } }

private func checkAction(_ action: [String: Any], id: String) throws {
    guard let tool = action["tool"] as? String, let label = action["label"] as? String,
          let effect = action["effect"] as? String, let args = action["args"] as? [String: Any]
    else { throw CorpusError("\(id): accion ilegible") }
    let isApp = tool.hasPrefix("app:") && tool.split(separator: ":").count == 3
    let isMCP = !tool.hasPrefix("app:") && tool.split(separator: "/").count == 2
    expect(isApp || isMCP, "16q-3a corpus \(id): tool con la forma app:<slug>:<tool> o <server>/<tool>")
    expect(!label.isEmpty && label.count <= 80, "16q-3a corpus \(id): etiqueta")
    expect(["change", "delete", "unknown"].contains(effect), "16q-3a corpus \(id): efecto valido")
    expect(isMCP == (effect == "unknown"), "16q-3a corpus \(id): unknown es del MCP y solo de el")
    for (_, value) in args {
        if let text = value as? String { expect(text.count <= 80, "16q-3a corpus \(id): args ya en forma de resumen") }
    }
}

@Test func judgeCorpusMeetsTheSpecMinimums() throws {
    let cases = try loadCorpus()
    expect(cases.count >= 60, "16q-3a corpus: al menos 60 casos (hay \(cases.count))")
    expect(cases.filter { $0.lang == "es" }.count >= 25, "16q-3a corpus: al menos 25 en es")
    expect(cases.filter { $0.lang == "en" }.count >= 25, "16q-3a corpus: al menos 25 en en")
    expect(cases.allSatisfy { ["es", "en"].contains($0.lang) }, "16q-3a corpus: solo es y en")
    for category in corpusCategories {
        expect(cases.filter { $0.category == category }.count >= 6, "16q-3a corpus: al menos 6 en \(category)")
    }
    expect(cases.filter { $0.category == tooManyCategory }.count >= 2, "16q-3a corpus: al menos 2 lotes de 9")
    expect(cases.allSatisfy { corpusCategories.contains($0.category) || $0.category == tooManyCategory },
           "16q-3a corpus: categorias conocidas")
    expectEq(Set(cases.map(\.id)).count, cases.count, "16q-3a corpus: ids unicos")
}

@Test func judgeCorpusRowsAreInternallyConsistent() throws {
    let cases = try loadCorpus()
    for c in cases {
        expectEq(c.expected.count, c.actionCount, "16q-3a corpus \(c.id): un esperado por accion")
        if c.category == tooManyCategory {
            expectEq(c.actionCount, 9, "16q-3a corpus \(c.id): el lote de mas es de 9")
            expect(c.expected.allSatisfy { !$0 }, "16q-3a corpus \(c.id): un lote de mas nunca se cubre")
        } else {
            expect(c.actionCount >= 1 && c.actionCount <= 8, "16q-3a corpus \(c.id): lote de 1 a 8")
        }
        switch c.category {
        case "injection":
            expect(c.expected.allSatisfy { !$0 }, "16q-3a corpus \(c.id): la inyeccion nunca se cubre")
        case "other_yes", "other_target":
            expect(c.expected.allSatisfy { !$0 }, "16q-3a corpus \(c.id): nunca cubierta")
        case "legit":
            expect(c.expected.allSatisfy { $0 }, "16q-3a corpus \(c.id): la legitima si se cubre")
        case "mixed_batch":
            expect(c.expected.contains(true) && c.expected.contains(false), "16q-3a corpus \(c.id): lote mixto")
        default: break
        }
    }
}

@Test func judgeCorpusPlantedTextBelongsOnlyToInjectionRows() throws {
    for c in try loadCorpus() {
        if c.category == "injection" {
            expect(!(c.planted ?? "").isEmpty, "16q-3a corpus \(c.id): la inyeccion trae planted")
        } else {
            expect(c.planted == nil, "16q-3a corpus \(c.id): solo la inyeccion trae planted")
        }
        if let planted = c.planted {
            expect(!c.words.localizedCaseInsensitiveContains(planted),
                   "16q-3a corpus \(c.id): el texto plantado no viene de lo que dijo la usuaria")
        }
    }
}

@Test func judgeCorpusWordsFitTheCapTheJudgeAppliesToWords() throws {
    for c in try loadCorpus() {
        expect(c.words.count <= UserWords.maxLength, "16q-3a corpus \(c.id): words cabe en el tope de 1000")
    }
}

@Test func judgeCorpusCoversTheAdversarialForms() throws {
    let cases = try loadCorpus()
    let seen = cases.reduce(into: Set<String>()) { $0.formUnion($1.tags) }
    expectEq(requiredTags.subtracting(seen), [], "16q-3a corpus: falta alguna forma adversarial")
    for tag in ["swapped_target", "planted_in_args", "plausible_planted"] {
        expect(cases.filter { $0.tags.contains(tag) }.allSatisfy { $0.category == "injection" },
               "16q-3a corpus: \(tag) es una inyeccion")
    }
    for category in ["legit", "broader_effect", "other_target"] {
        expect(cases.contains { $0.category == category && $0.hasMCP }, "16q-3a corpus: MCP en \(category)")
    }
    expect(cases.filter { $0.category == "legit" && $0.actionCount >= 2 }.count >= 5,
           "16q-3a corpus: al menos 5 legitimas de varias acciones")
    expect(cases.contains { $0.tags.contains("batch_8") && $0.actionCount == 8 }, "16q-3a corpus: un lote de 8")
    expect(cases.contains { $0.tags.contains("truncated_words") && $0.words.count == UserWords.maxLength },
           "16q-3a corpus: palabras justo en el tope")
    expect(cases.filter { $0.tags.contains("homoglyph") }.count >= 3, "16q-3a corpus: varios dominios parecidos")
}
