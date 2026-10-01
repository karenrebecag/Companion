import CompanionCore
import Foundation
import Testing

// DM1a. The composer copies the choice it was given. A perfect provider
// recovers every labeled action; a made-up id never becomes an argument.

private struct OrdenFixture: Sendable {
    var id: String
    var texto: String
    var accion: String
    var irreversible: Bool
    var strings: [String: String]
    var submit: Bool?
}

@Test func dm1ChoiceValidationRejectsABadDistribution() {
    let yesNo = DecisionQuestion(id: "gate", kind: .yesNo, instructions: "")
    let ok = DecisionAnswer(choice: "yes", distribution: ["yes": 0.8, "no": 0.2], confidence: 0.9)
    expectEq(ok.validated(for: yesNo)?.choice, "yes", "yes/no valido")
    let invented = DecisionAnswer(choice: "maybe", distribution: ["yes": 0.5, "no": 0.5], confidence: 0.5)
    expect(invented.validated(for: yesNo) == nil, "maybe no estaba ofrecido")
    let extra = DecisionAnswer(
        choice: "yes", distribution: ["yes": 0.5, "no": 0.5, "maybe": 0], confidence: 0.5)
    expect(extra.validated(for: yesNo) == nil, "una clave de mas")
    let short = DecisionAnswer(choice: "yes", distribution: ["yes": 1], confidence: 1)
    expect(short.validated(for: yesNo) == nil, "falta un id")
    let fat = DecisionAnswer(choice: "yes", distribution: ["yes": 0.9, "no": 0.9], confidence: 0.8)
    expect(fat.validated(for: yesNo) == nil, "no suma 1")
    let liar = DecisionAnswer(choice: "yes", distribution: ["yes": 0.2, "no": 0.8], confidence: 0.9)
    expect(liar.validated(for: yesNo) == nil, "el nombre no es el modo")
    let broken = DecisionAnswer(choice: "yes", distribution: ["yes": .nan, "no": 0.2], confidence: 0.5)
    expect(broken.validated(for: yesNo) == nil, "NaN")

    let wide = DecisionQuestion(id: "n", kind: .score, instructions: "", levels: 99)
    expectEq(wide.offeredIds.count, 10, "score se queda en 10")
    let narrow = DecisionQuestion(id: "n", kind: .score, instructions: "", levels: 1)
    expectEq(narrow.offeredIds, ["1", "2"], "score de un nivel no es una distribucion")
    expectEq(DecisionMath.sharpness(["a": 1, "b": 0, "c": 0]), 1, "masa puntual")
    expect(abs(DecisionMath.sharpness(["a": 1.0 / 3, "b": 1.0 / 3, "c": 1.0 / 3])) < 1e-9, "plana")
}

@Test func dm1TwoOrdersAverageOutOfAPositionBias() {
    let ids = ["none", "open_app"]
    let forward = DecisionAnswer(
        choice: "none", distribution: ["none": 0.62, "open_app": 0.38], confidence: 0.3)
    let reversed = DecisionAnswer(
        choice: "open_app", distribution: ["none": 0.30, "open_app": 0.70], confidence: 0.4)
    expectEq(DecisionMath.average(forward, reversed, ids: ids)?.choice, "open_app",
             "el promedio deshace el sesgo de cada orden")
    let tie = DecisionAnswer(
        choice: "none", distribution: ["none": 0.5, "open_app": 0.5], confidence: 0)
    expect(DecisionMath.average(tie, tie, ids: ids) == nil, "un empate no se rifa")
}

@Test func dm1ThresholdsConfirmIrreversibleAndTrustOnlyTheReversibleLine() {
    func at(
        _ action: DecisionAction, _ risk: PlanRisk, _ confidence: Double,
        complete: Bool = true, directed: Bool = false, trust: Double? = nil
    ) -> PlanDisposition {
        PlanThreshold.evaluate(
            action: action, risk: risk, confidence: confidence,
            argumentsComplete: complete, directed: directed, trust: trust)
    }
    expectEq(at(.openApp, .reversible, 0.6), .act, "reversible en 0.6 actua")
    expectEq(at(.openApp, .reversible, 0.59), .arbitrate, "por debajo arbitra")
    expectEq(at(.system, .irreversible, 0.99), .confirm, "0.99 irreversible igual confirma")
    expectEq(at(.system, .irreversible, 0.8), .confirm, "la banda alta tambien confirma")
    expectEq(at(.system, .irreversible, 0.6), .confirm, "0.6 irreversible confirma")
    expectEq(at(.system, .irreversible, 0.59), .arbitrate, "bajo 0.6 irreversible arbitra")
    expectEq(at(.system, .irreversible, 0.99, trust: 1), .confirm, "el trust no salta la confirmacion")
    expectEq(at(.openApp, .reversible, 0.4, trust: 1), .act, "trust 1 baja la linea reversible a 0.35")
    expectEq(at(.openApp, .reversible, 0.4, trust: nil), .arbitrate, "sin trust 0.4 no actua")
    expectEq(at(.task, .irreversible, 0.99), .delegate, "la tarea la hace el especialista")
    expectEq(at(.none, .reversible, 0.99), .ignore, "none sin blanco es conversacion")
    expectEq(at(.none, .reversible, 0.99, directed: true), .arbitrate, "none sobre una orden clara arbitra")
    expectEq(at(.openApp, .reversible, 0.99, complete: false), .arbitrate, "sin argumento no actua")
    expectEq(at(.openApp, .reversible, .nan), .arbitrate, "NaN no actua")
    expectEq(AppTrust.threshold(for: 1), 0.35, "trust 1")
    expectEq(AppTrust.threshold(for: 0), 0.75, "trust 0")
    expectEq(AppTrust.threshold(for: 0.5), 0.55, "trust medio")
}

@Test func dm1GuardsStopARepeatedMutation() {
    var tracker = RejectionTracker()
    var effect = RejectionTracker.Effect.none
    for _ in 0..<2 {
        (tracker, effect) = tracker.observing("abre Safari", rejected: true)
        expectEq(effect, .none, "todavia no son tres")
    }
    (tracker, effect) = tracker.observing("Abre   safari", rejected: true)
    expectEq(effect, .arbitrate, "el tercer rechazo, aunque cambie las mayusculas, arbitra")
    (tracker, effect) = tracker.observing("otra orden", rejected: true)
    expectEq(effect, .none, "otra orden no hereda la racha")
    (tracker, effect) = tracker.observing("abre Safari", rejected: false)
    expectEq(effect, .none, "un acierto corta la racha")
    for _ in 0..<3 {
        (tracker, effect) = tracker.observing("abre Safari", rejected: true)
    }
    expectEq(effect, .stop, "el segundo incidente para")

    var ledger = MutationLedger()
    var already = false
    (ledger, already) = ledger.recording("system:empty_trash", attempt: "turn-1")
    expect(!already, "la primera vez se registra")
    (ledger, already) = ledger.recording("system:empty_trash", attempt: "turn-1")
    expect(already, "la segunda vez en el mismo intento es un reintento")
    (ledger, already) = ledger.recording("system:empty_trash", attempt: "turn-2")
    expect(!already, "un intento nuevo no hereda el registro del anterior")
    (ledger, already) = ledger.recording("type_text:gracias#false", attempt: "turn-3")
    expect(!already, "gracias otra vez, en otro turno, no es un reintento")
}

@Test func dm1ShortcutEnterIsIrreversibleButSaveIsNot() {
    expectEq(Plan.risk(action: .shortcut, args: ["shortcut": .text("enter")]), .irreversible,
             "enter envia el mensaje del chat, igual que send_message")
    expectEq(Plan.risk(action: .shortcut, args: ["shortcut": .text("save")]), .reversible,
             "guardar se deshace, enter no")
    let plan = Plan(
        utterance: "presiona enter", action: .shortcut, args: ["shortcut": .text("enter")],
        confidence: 0.9, risk: .irreversible, disposition: .confirm)
    expectEq(plan.retryKey, "shortcut:enter", "enter no se reintenta en el mismo intento")
}

@Test func dm1ShortlistIsTheOnlyChoice() throws {
    let list = ArbitrationShortlist.build(
        utterance: "abre Safari",
        world: DecisionWorld(apps: ["Safari", "Mail"], sites: []),
        actionMass: ["open_app": 0.5, "volume": 0.3, "none": 0.15, "task": 0.05])
    expect(list.accepts("open_app:Safari"), "safari esta")
    expect(!list.accepts("open_app:Mail"), "mail no fue candidato")
    expect(list.accepts("volume:mute"), "volumen entra con la accion")
    expect(!list.accepts("run_shell"), "no hay tool call libre")
    expect(!list.entries.contains { $0.action == .task }, "task quedo fuera del top 3")
    expect(list.entry(for: "volume:mute")?.args["op"] == .text("mute"), "el id vuelve a ser la op")

    let raw = try JSONSerialization.jsonObject(with: Data(list.choiceSchema().utf8))
    let object = raw as? [String: Any]
    let parameters = object?["parameters"] as? [String: Any]
    let choice = (parameters?["properties"] as? [String: Any])?["choice"] as? [String: Any]
    expectEq(choice?["enum"] as? [String] ?? [], list.allowedIds, "el schema enum es la shortlist")
    expect(parameters?["additionalProperties"] as? Bool == false, "el objeto esta cerrado")

    let empty = ArbitrationShortlist(entries: [])
    do {
        _ = try empty.choiceSchema()
        expect(false, "una shortlist vacia no puede ofrecer enum: []")
    } catch {
        expect(true, "vacia lanza en vez de devolver un schema roto")
    }

    expect(ArbitrationTier.needsStrong(fastConfidence: 0.49), "el rapido duda")
    expect(!ArbitrationTier.needsStrong(fastConfidence: 0.5), "0.5 se queda")
    let rule = LearnedAppRule(app: "Safari", trust: 2, rule: String(repeating: "a", count: 201))
    expectEq(rule.trust, 1, "trust se acota")
    expectEq(rule.rule.count, 200, "la regla cabe en 200")
}

@Test func dm1ArbitratedEntryStillConfirmsWhatIsIrreversible() {
    let trash = ShortlistEntry(
        id: "system:empty_trash", action: .system, args: ["op": .text("empty_trash")], mass: 0.6)
    expectEq(
        trash.plan(utterance: "vacia la papelera", confidence: 0.99, trust: nil).disposition,
        .confirm, "N2 seguro de si mismo no salta la confirmacion")

    let quit = ShortlistEntry(
        id: "shortcut:quit_app", action: .shortcut, args: ["shortcut": .text("quit_app")], mass: 0.6)
    expectEq(
        quit.plan(utterance: "cierra la app", confidence: 0.99, trust: nil).disposition,
        .confirm, "quit_app arbitrado tambien confirma")

    let enter = ShortlistEntry(
        id: "shortcut:enter", action: .shortcut, args: ["shortcut": .text("enter")], mass: 0.6)
    expectEq(
        enter.plan(utterance: "presiona enter", confidence: 0.99, trust: nil).disposition,
        .confirm, "enter arbitrado tambien confirma")

    let safari = ShortlistEntry(
        id: "open_app:Safari", action: .openApp, args: ["app": .text("Safari")], mass: 0.6)
    expectEq(
        safari.plan(utterance: "abre Safari", confidence: 0.9, trust: nil).disposition,
        .act, "reversible a 0.9 actua")

    let none = ShortlistEntry(id: "none", action: .none, args: [:], mass: 0.6)
    expectEq(
        none.plan(utterance: "que hora es la cena", confidence: 0.9, trust: nil).disposition,
        .ignore, "N2 ya arbitro none, no vuelve a arbitrar")
}

@Test func dm1TiedActionMassSurvivesIntoTheShortlist() async {
    // A judge that always splits open_app/volume 50/50, whichever order it
    // was asked in. Averaging the two orders is a genuine tie: no single
    // action wins, but the blended masses are the shortlist's only input.
    let tiedActions: Set<String> = ["open_app", "volume"]
    let tiedJudge = ScriptedDecision { question in
        guard question.id == DecisionHead.action else { return nil }
        var distribution: [String: Double] = [:]
        for id in question.offeredIds { distribution[id] = 0 }
        for id in question.offeredIds where tiedActions.contains(id) { distribution[id] = 0.5 }
        return DecisionAnswer(choice: "open_app", distribution: distribution, confidence: 0.5)
            .validated(against: question.offeredIds)
    }
    let world = DecisionWorld(apps: ["Safari"], sites: [])
    let plan = await Plan.compose(utterance: "abre Safari o sube el volumen", world: world, provider: tiedJudge)
    expectEq(plan.disposition, .arbitrate, "un empate real no se rifa solo")
    expect(abs((plan.actionMass["open_app"] ?? 0) - 0.5) < 1e-6, "open_app conserva su masa del empate")
    expect(abs((plan.actionMass["volume"] ?? 0) - 0.5) < 1e-6, "volume conserva su masa del empate")

    let shortlist = ArbitrationShortlist.build(
        utterance: "abre Safari o sube el volumen", world: world, actionMass: plan.actionMass)
    expect(shortlist.accepts("open_app:Safari"), "el empate no le cuesta a N2 la opcion de Safari")

    let brokenJudge = ScriptedDecision { _ in nil }
    let broken = await Plan.compose(utterance: "abre Safari", world: world, provider: brokenJudge)
    expectEq(broken.actionMass, [String: Double](), "sin respuesta del juez no hay masa que repartir")
}

@Test func dm1SafariActsAndTrashConfirms() async {
    let safari = fixture("abre Safari", "open_app", ["app": "Safari"], irreversible: false)
    let opened = await Plan.compose(
        utterance: safari.texto,
        world: DecisionWorld(apps: ["Safari", "Mail"], sites: []),
        provider: perfect(safari))
    expectEq(opened.action, .openApp, "safari")
    expectEq(opened.disposition, .act, "abrir no pregunta")
    expectEq(opened.args["app"], .text("Safari"), "safari")
    expect(opened.retryKey == nil, "abrir no es una mutacion")

    let trash = fixture("vacia la papelera", "system", ["op": "empty_trash"], irreversible: true)
    let emptying = await Plan.compose(
        utterance: trash.texto, world: DecisionWorld(sites: []), provider: perfect(trash))
    expectEq(emptying.action, .system, "papelera")
    expectEq(emptying.disposition, .confirm, "irreversible confirma")
    expectEq(emptying.risk, .irreversible, "papelera")
    expect(emptying.confidence > 0.9, "confirma aunque este seguro")
    expectEq(emptying.retryKey, "system:empty_trash", "vaciar no se reintenta")

    let dinner = fixture("what time is dinner", "none", [:], irreversible: false)
    let ignored = await Plan.compose(
        utterance: dinner.texto,
        world: DecisionWorld(apps: ["Safari"]),
        provider: perfect(dinner))
    expectEq(ignored.disposition, .ignore, "la cena no es una orden")

    let refused = ScriptedDecision { question in
        if question.id == DecisionHead.action {
            return peaked("none", question.offeredIds)
        }
        return nil
    }
    let doubtful = await Plan.compose(
        utterance: "abre Safari",
        world: DecisionWorld(apps: ["Safari"], sites: []),
        provider: refused)
    expectEq(doubtful.action, .none, "el juez dijo none")
    expectEq(doubtful.disposition, .arbitrate, "none sobre Safari arbitra")

    let invented = ScriptedDecision { question in
        if question.id == DecisionHead.action { return peaked("open_app", question.offeredIds) }
        return DecisionAnswer(choice: "Preview", distribution: ["Preview": 1], confidence: 1)
    }
    let blocked = await Plan.compose(
        utterance: "abre Safari",
        world: DecisionWorld(apps: ["Safari"], sites: []),
        provider: invented)
    expectEq(blocked.disposition, .arbitrate, "Preview no se ejecuta")
    expect(blocked.args["app"] == nil, "el argumento no se copio")
}

@Test func dm1PerfectProviderRecoversEveryLabeledAction() async throws {
    let rows = try loadOrdenFixtures()
    expect(rows.count >= 150, "el conjunto tiene \(rows.count) filas")
    let apps = Array(Set(rows.compactMap { $0.accion == "open_app" ? $0.strings["app"] : nil })).sorted()
    var failures: [String] = []
    for row in rows {
        let plan = await Plan.compose(
            utterance: row.texto, world: world(for: row, apps: apps), provider: perfect(row))
        failures.append(contentsOf: problems(plan, row))
    }
    expect(failures.isEmpty, "\(failures.count) filas: " + failures.prefix(8).joined(separator: " | "))
}

// MARK: - fixtures

private func fixture(
    _ texto: String, _ accion: String, _ strings: [String: String], irreversible: Bool
) -> OrdenFixture {
    OrdenFixture(
        id: "local", texto: texto, accion: accion, irreversible: irreversible,
        strings: strings, submit: nil)
}

private func perfect(_ row: OrdenFixture) -> ScriptedDecision {
    ScriptedDecision { question in
        guard let choice = labeledChoice(question, row) else { return nil }
        return peaked(choice, question.offeredIds)
    }
}

private func peaked(_ choice: String, _ ids: [String]) -> DecisionAnswer? {
    guard !ids.isEmpty, Set(ids).contains(choice) else { return nil }
    var distribution: [String: Double] = [:]
    if ids.count == 1 {
        distribution[choice] = 1
    } else {
        let share = 0.01 / Double(ids.count - 1)
        var rest = 0.0
        for id in ids where id != choice {
            distribution[id] = share
            rest += share
        }
        distribution[choice] = 1 - rest
    }
    return DecisionAnswer(
        choice: choice, distribution: distribution,
        confidence: DecisionMath.sharpness(distribution)
    ).validated(against: ids)
}

private func labeledChoice(_ question: DecisionQuestion, _ row: OrdenFixture) -> String? {
    let options = question.options
    func named(_ wanted: String?) -> String? {
        guard let wanted else { return nil }
        return options.first { $0.id == wanted }?.id
    }
    switch question.id {
    case DecisionHead.action:
        return options.contains { $0.id == row.accion } ? row.accion : nil
    case DecisionHead.app:
        let want = row.strings["app"]?.lowercased()
        return options.first { $0.id.lowercased() == want }?.id
    case DecisionHead.site:
        return options.first { $0.detail == row.strings["url"] }?.id
    case DecisionHead.file:
        return options.first { $0.id == row.strings["path"] }?.id
    case DecisionHead.skill:
        return options.first { $0.id == row.strings["name"] }?.id
    case DecisionHead.query:
        return options.first { $0.detail == row.strings["query"] }?.id
    case DecisionHead.text:
        if let exact = options.first(where: { $0.detail == row.strings["text"] }) { return exact.id }
        return options.first?.id
    case DecisionHead.goal:
        if let exact = options.first(where: { $0.detail == row.strings["goal"] }) { return exact.id }
        return options.first?.id
    case DecisionHead.submit:
        let wanted = row.submit == true ? "yes" : "no"
        return options.contains { $0.id == wanted } ? wanted : nil
    case DecisionHead.volume, DecisionHead.media, DecisionHead.system:
        return named(row.strings["op"])
    case DecisionHead.shortcut:
        return named(row.strings["shortcut"])
    case DecisionHead.scrollDirection:
        return named(row.strings["direction"])
    case DecisionHead.scrollAmount:
        return named(row.strings["amount"])
    default:
        return nil
    }
}

private func world(for row: OrdenFixture, apps: [String]) -> DecisionWorld {
    var world = DecisionWorld(apps: apps)
    if row.accion == "open_file", let path = row.strings["path"] {
        world.files = [FileCandidate(path: path)]
    }
    if row.accion == "read_skill", let name = row.strings["name"] {
        world.skills = [name]
    }
    return world
}

private func contained(_ needle: String, in hay: String) -> Bool {
    CandidateSets.fold(hay).contains(CandidateSets.fold(needle))
}

private func problems(_ plan: Plan, _ row: OrdenFixture) -> [String] {
    var found: [String] = []
    func bad(_ note: String) { found.append("\(row.id) \(note)") }
    if plan.action.rawValue != row.accion { bad("accion \(plan.action.rawValue)") }
    if plan.confidence < 0.8 { bad(String(format: "confianza %.3f", plan.confidence)) }
    if (plan.risk == .irreversible) != row.irreversible { bad("riesgo \(plan.risk.rawValue)") }
    let wanted: PlanDisposition
    if row.accion == "task" { wanted = .delegate }
    else if row.accion == "none" { wanted = .ignore }
    else if row.irreversible { wanted = .confirm }
    else { wanted = .act }
    if plan.disposition != wanted { bad("disposition \(plan.disposition.rawValue)") }
    for span in CandidateSets.textSpans(row.texto) where !contained(span.detail, in: row.texto) {
        bad("span inventado \(span.detail)")
    }
    switch row.accion {
    case "open_app":
        if plan.args != ["app": .text(row.strings["app"] ?? "")] { bad("args \(plan.args)") }
    case "open_url":
        if plan.args != ["url": .text(row.strings["url"] ?? "")] { bad("args \(plan.args)") }
    case "open_file":
        if plan.args != ["path": .text(row.strings["path"] ?? "")] { bad("args \(plan.args)") }
    case "read_skill":
        if plan.args != ["name": .text(row.strings["name"] ?? "")] { bad("args \(plan.args)") }
    case "find_places":
        if plan.args != ["query": .text(row.strings["query"] ?? "")] { bad("args \(plan.args)") }
    case "volume", "media", "system":
        if plan.args != ["op": .text(row.strings["op"] ?? "")] { bad("args \(plan.args)") }
    case "shortcut":
        if plan.args != ["shortcut": .text(row.strings["shortcut"] ?? "")] { bad("args \(plan.args)") }
    case "scroll":
        let want: [String: PlanValue] = [
            "direction": .text(row.strings["direction"] ?? ""),
            "amount": .text(row.strings["amount"] ?? ""),
        ]
        if plan.args != want { bad("args \(plan.args)") }
    case "type_text":
        freeText(plan, row, key: "text", bad: bad)
        if plan.args["submit"] != .flag(row.submit ?? false) { bad("submit \(String(describing: plan.args["submit"]))") }
    case "task":
        freeText(plan, row, key: "goal", bad: bad)
    case "list_apps", "none":
        if !plan.args.isEmpty { bad("args \(plan.args)") }
    default:
        bad("accion sin chequeo")
    }
    return found
}

private func freeText(
    _ plan: Plan, _ row: OrdenFixture, key: String, bad: (String) -> Void
) {
    let want = row.strings[key] ?? ""
    guard case .text(let got) = plan.args[key] else {
        bad("sin \(key)")
        return
    }
    if contained(want, in: row.texto) {
        if got != want { bad("\(key) \(got) != \(want)") }
    } else if !contained(got, in: row.texto) {
        bad("\(key) inventado \(got)")
    }
}

private func loadOrdenFixtures() throws -> [OrdenFixture] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent("docs/research/decision-model/dataset/ordenes.jsonl")
    let content = try String(contentsOf: url, encoding: .utf8)
    return try content.split(separator: "\n", omittingEmptySubsequences: true).map { line in
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        guard let object,
              let id = object["id"] as? String,
              let texto = object["texto"] as? String,
              let accion = object["accion"] as? String,
              let irreversible = jsonFlag(object["irreversible"]),
              let args = object["args"] as? [String: Any]
        else { throw FixtureError("fila ilegible") }
        var strings: [String: String] = [:]
        var submit: Bool?
        for (key, value) in args {
            if let text = value as? String { strings[key] = text }
            if key == "submit", let flag = jsonFlag(value) { submit = flag }
        }
        return OrdenFixture(
            id: id, texto: texto, accion: accion, irreversible: irreversible,
            strings: strings, submit: submit)
    }
}

private func jsonFlag(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID()
    else { return nil }
    return number.boolValue
}

private struct FixtureError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
