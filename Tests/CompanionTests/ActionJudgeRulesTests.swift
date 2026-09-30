@testable import CompanionCore
import Foundation
import Testing

// 16q-3a: the pure rules around the judge: local rules, provider route and settings.

private let invalid = JudgeVerdict.failed(.invalid)

private func app(_ json: String) -> ProposedAction? {
    ProposedAction.app(toolName: "app:slack:slack-send-message", label: "Send Message · Slack",
                       group: .crearYCambiar, argumentsJSON: json)
}

private func keys(_ count: Int) -> String {
    let body = (0 ..< count).map { #""k\#(String(format: "%02d", $0))":1"# }.joined(separator: ",")
    return "{\(body)}"
}

// MARK: - Local rule: incomplete never reaches the model

private func request(_ actions: [ProposedAction]) -> ActionJudgeRequest? {
    UserWords(heard: "hola").flatMap { ActionJudgeRequest(words: $0, actions: actions, pipeline: .classic) }
}

@Test func localRuleFailsAnIncompleteActionWithoutAskingTheModel() {
    guard let good = app(#"{"channel":"ventas"}"#), let bad = app(keys(20)) else {
        Issue.record("fixtures")
        return
    }
    expect(ActionJudgeLocalRules.verdict(for: good) == nil, "16q-3a regla: una completa se pregunta al modelo")
    expectEq(ActionJudgeLocalRules.verdict(for: bad), invalid, "16q-3a regla: una incompleta es failed(invalid)")
    guard let req = request([good, bad, good]) else {
        Issue.record("fixtures")
        return
    }
    expectEq(ActionJudgeLocalRules.askable(in: req).count, 2, "16q-3a regla: al modelo solo llegan las completas")
    let combined = ActionJudgeLocalRules.combine(req, modelVerdicts: [.covered, .notCovered(.notAsked)])
    expectEq(combined, [.covered, invalid, .notCovered(.notAsked)],
             "16q-3a regla: el hueco de la incompleta queda fallado y el orden se conserva")
}

@Test func localRuleNeverLetsTheModelCoverAnIncompleteAction() {
    guard let bad = app("garbage"), let good = app(#"{"channel":"ventas"}"#), let req = request([bad, good]) else {
        Issue.record("fixtures")
        return
    }
    let hostile = ActionJudgeLocalRules.combine(req, modelVerdicts: [.covered, .covered])
    expectEq(hostile.first, invalid, "16q-3a regla: aunque el modelo conteste de mas, la incompleta falla")
    expectEq(hostile, [invalid, invalid], "16q-3a regla: la cuenta no cuadra, ninguna del modelo se cree")
    expectEq(ActionJudgeLocalRules.combine(req, modelVerdicts: []), [invalid, invalid],
             "16q-3a regla: sin veredictos del modelo todo falla")
}

@Test func localRuleAllIncompleteAsksNothing() {
    guard let a = app("x"), let b = app("[]"), let req = request([a, b]) else {
        Issue.record("fixtures")
        return
    }
    expectEq(ActionJudgeLocalRules.askable(in: req).count, 0, "16q-3a regla: nada que preguntar")
    expectEq(ActionJudgeLocalRules.combine(req, modelVerdicts: []), [invalid, invalid],
             "16q-3a regla: todo fallado sin llamar al modelo")
}

@Test func localRulePassesModelVerdictsThroughWhenEverythingIsComplete() {
    guard let a = app(#"{"channel":"a"}"#), let b = app(#"{"channel":"b"}"#), let req = request([a, b]) else {
        Issue.record("fixtures")
        return
    }
    expectEq(ActionJudgeLocalRules.combine(req, modelVerdicts: [.notCovered(.otherTarget), .covered]),
             [.notCovered(.otherTarget), .covered], "16q-3a regla: sin locales, el modelo manda")
}

// MARK: - Provider route

@Test func judgeRouteTableIsExhaustive() {
    let cerebras = ProviderDescriptor.cerebras
    let openAI = ProviderDescriptor.openAI
    let confirmed = "qwen-confirmed:7b"
    let keySets: [Set<SecretKey>] = [[], [.openAI], [.cerebras], [.openAI, .cerebras]]
    for keys in keySets {
        for model in [nil, confirmed] {
            let rt = ActionJudgeRoute.provider(pipeline: .realtime, keys: keys, ollamaModel: model)
            expectEq(rt?.id, openAI.id, "16q-3a ruta: realtime siempre OpenAI (\(keys.count) claves)")
            expectEq(rt?.model, HoldBrainCatalog.openAIModel, "16q-3a ruta: realtime gpt-4o-mini")
        }
    }
    func classic(_ keys: Set<SecretKey>, _ model: String?) -> ProviderDescriptor? {
        ActionJudgeRoute.provider(pipeline: .classic, keys: keys, ollamaModel: model)
    }
    let rows: [(keys: Set<SecretKey>, model: String?, id: String?, served: String?)] = [
        ([.cerebras, .openAI], confirmed, cerebras.id, cerebras.model),
        ([.cerebras, .openAI], nil, cerebras.id, cerebras.model),
        ([.cerebras], confirmed, cerebras.id, cerebras.model),
        ([.cerebras], nil, cerebras.id, cerebras.model),
        ([.openAI], confirmed, openAI.id, HoldBrainCatalog.openAIModel),
        ([.openAI], nil, openAI.id, HoldBrainCatalog.openAIModel),
        ([], confirmed, ProviderDescriptor.ollama.id, confirmed),
        ([], nil, nil, nil),
        ([.groq, .openRouter], confirmed, ProviderDescriptor.ollama.id, confirmed),
        ([.groq, .openRouter], nil, nil, nil),
    ]
    for row in rows {
        let got = classic(row.keys, row.model)
        expectEq(got?.id, row.id, "16q-3a ruta: \(row.keys.count) claves, ollama \(row.model ?? "no")")
        expectEq(got?.model, row.served, "16q-3a ruta: el modelo de \(row.id ?? "nada")")
    }
    expect(confirmed != ProviderDescriptor.ollama.model, "16q-3a ruta: el fixture no coincide con el tag estatico")
}

@Test func judgeRouteTreatsABlankOllamaModelAsNotConfirmed() {
    expect(ActionJudgeRoute.provider(pipeline: .classic, keys: [], ollamaModel: "") == nil,
           "16q-3a ruta: un modelo vacio no es confirmado")
    expect(ActionJudgeRoute.provider(pipeline: .classic, keys: [], ollamaModel: "  \n") == nil,
           "16q-3a ruta: ni uno en blanco")
}

// MARK: - Settings

@Test func actionJudgeSettingsReadTheEnvironment() {
    expectEq(ActionJudgeSettings(environment: [:]).mode, .shadow, "16q-3a config: sombra por defecto (D4)")
    expectEq(ActionJudgeSettings(environment: ["COMPANION_ACTION_JUDGE": "shadow"]).mode, .shadow, "16q-3a config: shadow")
    expectEq(ActionJudgeSettings(environment: ["COMPANION_ACTION_JUDGE": "garbage"]).mode, .shadow,
             "16q-3a config: un valor raro no apaga la metrica")
    expectEq(ActionJudgeSettings(environment: ["COMPANION_ACTION_JUDGE": ""]).mode, .shadow,
             "16q-3a config: vacio tampoco apaga")
    let enforce = ActionJudgeSettings(environment: ["COMPANION_ACTION_JUDGE": "enforce"])
    expectEq(enforce.mode, .shadow, "16q-3a config: enforce se lee como shadow (invariante 8)")
    expect(enforce.enforceRequested, "16q-3a config: queda dicho para dejar la linea de log")
    expect(!ActionJudgeSettings(environment: [:]).enforceRequested, "16q-3a config: sin enforce no hay aviso")
    expectEq(ActionJudgeSettings(environment: [:]).timeout, 2.5, "16q-3a config: timeout 2,5 s")
    expectEq(ActionJudgeSettings(environment: [:]).maxActions, 8, "16q-3a config: 8 acciones")
    expectEq(Config().judge.timeout, 2.5, "16q-3a config: expuesto como Config.judge")
}

@Test func actionJudgeSettingsAcceptEveryWayOfSayingOff() {
    for value in ["off", "OFF", "Off", " off ", "\toff\n", "0", " 0 ", "false", "FALSE", "False", " false\n"] {
        expectEq(ActionJudgeSettings(environment: ["COMPANION_ACTION_JUDGE": value]).mode, .off,
                 "16q-3a config: \(value.debugDescription) apaga")
    }
    for value in ["no", "1", "true", "on", "disabled", "of"] {
        expectEq(ActionJudgeSettings(environment: ["COMPANION_ACTION_JUDGE": value]).mode, .shadow,
                 "16q-3a config: \(value) no apaga")
    }
    let loud = ActionJudgeSettings(environment: ["COMPANION_ACTION_JUDGE": " ENFORCE \n"])
    expectEq(loud.mode, .shadow, "16q-3a config: ENFORCE recortado sigue siendo shadow")
    expect(loud.enforceRequested, "16q-3a config: y deja el aviso")
    expect(!ActionJudgeSettings(environment: ["COMPANION_ACTION_JUDGE": "off"]).enforceRequested,
           "16q-3a config: off no pide enforce")
}
