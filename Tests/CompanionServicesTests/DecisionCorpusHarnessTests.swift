import CompanionCore
import CompanionServices
import Foundation
import Testing

// The corpus run: Plan.compose over every row of ordenes.jsonl, once per
// judge, reporting action accuracy, p50 latency and cost. It measures, it
// does not gate, and it reaches real services, so it runs only with
// COMPANION_LIVE_JUDGES=1:
//
//   COMPANION_LIVE_JUDGES=1 swift test --filter decisionCorpusHarness
//
// COMPANION_LIVE_JUDGES=ollama runs the local judge alone, without touching
// the Keychain.
//
// Ollama is measured when its daemon answers; Jev when the TypeSafe key is
// saved in Ajustes > Claves (read from the Keychain, never from the shell).

@Test func decisionCorpusHarness() async throws {
    let mode = ProcessInfo.processInfo.environment["COMPANION_LIVE_JUDGES"]
    guard mode == "1" || mode == "ollama" else { return }
    let rows = try loadCorpus()
    let apps = Array(Set(rows.compactMap { $0.accion == "open_app" ? $0.args["app"] : nil })).sorted()
    print("\nCORPUS: \(rows.count) rows")

    let ollamaMeter = MeteredTransport()
    let ollama = OllamaDecisionProvider(transport: ollamaMeter)
    await ollama.warm()
    let local = await run("ollama", provider: ollama, rows: rows, apps: apps)
    print(local.summary(costPerMtok: 0, tokens: 0))

    guard mode == "1" else { return }
    let secrets = KeychainSecretStore()
    let jevMeter = MeteredTransport()
    let jev = TypeSafeDecisionProvider(secrets: secrets, transport: jevMeter)
    guard jev.isConfigured else {
        print("jev: no TypeSafe key in Ajustes > Claves, skipped")
        return
    }
    let hosted = await run("jev", provider: jev, rows: rows, apps: apps)
    print(hosted.summary(costPerMtok: jevPricePerMtok, tokens: jevMeter.inputTokens))
    await measureDelegationHead(jev, rows: rows)
}

/// docs.typesafe.ai/models, jev-1.14.0: $0.042 per million input tokens;
/// output tokens are free.
private let jevPricePerMtok = 0.042

/// The rows #324 added as "answered directly / own tools, never delegates";
/// every `task` row is the other side: a hand-off the head must leave offered.
private let noDelegateRows: Set<String> = ["s178", "s179", "s180", "s181", "s182"]

private struct CorpusRow: Sendable {
    var id: String
    var texto: String
    var accion: String
    var args: [String: String]
}

private struct JudgeRun {
    var name: String
    var correct = 0
    var total = 0
    var millis: [Double] = []
    var misses: [String] = []

    func summary(costPerMtok: Double, tokens: Int) -> String {
        let sorted = millis.sorted()
        let p50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let cost = Double(tokens) / 1_000_000 * costPerMtok
        return "\(name): accuracy=\(correct)/\(total) p50=\(String(format: "%.0f", p50))ms "
            + "input_tokens=\(tokens) cost=$\(String(format: "%.6f", cost))\n"
            + "\(name) misses: " + misses.prefix(20).joined(separator: " | ")
    }
}

private func run(
    _ name: String, provider: any DecisionProvider, rows: [CorpusRow], apps: [String]
) async -> JudgeRun {
    var result = JudgeRun(name: name)
    let clock = ContinuousClock()
    for row in rows {
        let start = clock.now
        let plan = await Plan.compose(
            utterance: row.texto, world: world(for: row, apps: apps), provider: provider)
        let took = clock.now - start
        result.millis.append(Double(took.components.attoseconds) / 1e15
            + Double(took.components.seconds) * 1000)
        result.total += 1
        if plan.action.rawValue == row.accion {
            result.correct += 1
        } else {
            result.misses.append("\(row.id) \(row.accion)->\(plan.action.rawValue)")
        }
    }
    return result
}

private func measureDelegationHead(_ jev: TypeSafeDecisionProvider, rows: [CorpusRow]) async {
    var kept = 0, keptTotal = 0, withdrawn = 0, withdrawnTotal = 0
    var misses: [String] = []
    for row in rows where row.accion == "task" || noDelegateRows.contains(row.id) {
        let verdict = await jev.answer(DelegationHead.question(row.texto))
        let offers = DelegationHead.offersDelegate(utterance: row.texto, verdict)
        let label = "\(row.id) \(verdict?.choice ?? "-")@\(String(format: "%.2f", verdict?.confidence ?? 0))"
        if row.accion == "task" {
            keptTotal += 1
            if offers { kept += 1 } else { misses.append("withdrew " + label) }
        } else {
            withdrawnTotal += 1
            if !offers { withdrawn += 1 } else { misses.append("kept " + label) }
        }
    }
    print("jev delegation head: task rows keep delegate \(kept)/\(keptTotal), "
        + "no-delegate rows withdraw it \(withdrawn)/\(withdrawnTotal)\n"
        + "head misses: " + misses.joined(separator: " | "))
}

private func world(for row: CorpusRow, apps: [String]) -> DecisionWorld {
    var world = DecisionWorld(apps: apps)
    if row.accion == "open_file", let path = row.args["path"] {
        world.files = [FileCandidate(path: path)]
    }
    if row.accion == "read_skill", let name = row.args["name"] {
        world.skills = [name]
    }
    return world
}

private func loadCorpus() throws -> [CorpusRow] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("docs/research/decision-model/dataset/ordenes.jsonl")
    let content = try String(contentsOf: url, encoding: .utf8)
    return content.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
        let decoded: Any
        do {
            decoded = try JSONSerialization.jsonObject(with: Data(line.utf8))
        } catch {
            return nil
        }
        guard let object = decoded as? [String: Any],
              let id = object["id"] as? String,
              let texto = object["texto"] as? String,
              let accion = object["accion"] as? String
        else { return nil }
        let args = (object["args"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        return CorpusRow(id: id, texto: texto, accion: accion, args: args)
    }
}

/// Real network, counting what TypeSafe bills: `usage.input_tokens` from
/// each reply. Ollama's replies carry none, so its count stays zero.
private final class MeteredTransport: ChatTransport, @unchecked Sendable {
    private let inner = URLSessionChatTransport()
    private let lock = NSLock()
    private var _inputTokens = 0
    var inputTokens: Int { lock.withLock { _inputTokens } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await inner.data(for: request)
        let object: Any?
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            object = nil
        }
        if let usage = (object as? [String: Any])?["usage"] as? [String: Any],
           let tokens = usage["input_tokens"] as? Int {
            lock.withLock { _inputTokens += tokens }
        }
        return (data, response)
    }

    func lines(for request: URLRequest) async throws -> (
        status: Int, lines: AsyncThrowingStream<String, Error>
    ) {
        try await inner.lines(for: request)
    }

    func bytes(for request: URLRequest) async throws -> (
        status: Int, bytes: AsyncThrowingStream<Data, Error>
    ) {
        try await inner.bytes(for: request)
    }
}
