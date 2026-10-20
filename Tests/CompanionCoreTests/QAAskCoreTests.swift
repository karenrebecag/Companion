import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

@testable import CompanionCore

private let sentinel = "SENTINEL-\u{1F9EA}-9f3a"

private func finished(_ id: String = "t1") -> TurnRecord {
    var record = TurnRecord(turnId: id, conversationId: "c1", origin: "agent")
    record.status = .completed
    record.toolCalls = [TurnToolCall(
        index: 0, name: "open_app", arguments: #"{"name":"\#(sentinel)"}"#, ok: true, target: "Safari",
        output: "opened \(sentinel)", verified: false, band: "act", ownerCheck: "none")]
    record.statusLines = ["opened \(sentinel)"]
    record.reply = TurnReply(text: "hello \(sentinel)", isFailure: false)
    return record
}

@Test func everyQAToolIsAllowlistedAndInABucket() {
    for tool in QATool.allCases {
        expect(BridgeScope.allows(tool.rawValue), "\(tool.rawValue): en la allowlist")
        expect(!BridgeScope.isLocalOnly(tool.rawValue), "\(tool.rawValue): no es solo local")
    }
    expect(BridgePolicy.writeTools.contains("companion_ask"), "ask gasta del presupuesto de acciones")
    expect(BridgePolicy.readTools.contains("companion_wait_turn"), "wait_turn es lectura")
    expectEq(BridgePolicy.unbucketed(BridgeScope.bridgeTools), [], "ninguna tool sin cubo")
}

@Test func theQASpecsCarryTheRequiredArgumentsAndTheirLimits() {
    let ask = QATool.ask.spec(.en)
    expectEq(ask.required, ["text"], "ask pide text")
    let text = ask.properties.first { $0.name == "text" }
    expectEq(text?.maxBytes, 16_000, "tope de bytes del texto")
    expectEq(ask.properties.first { $0.name == "conversation" }?.allowed ?? [], ["current", "new"], "conversation")
    expectEq(QATool.waitTurn.spec(.es).required, ["turn_id"], "wait_turn pide turn_id")
}

@Test func withoutQATheResultCarriesLengthsAndNoWords() throws {
    let json = TurnResult.json(finished(), includeText: false)
    expect(!json.contains(sentinel), "ningun texto sale sin QA")
    expect(json.contains(#""length":"#), "la respuesta vuelve como longitud")
    expect(json.contains(#""output_length":"#), "y el output tambien")
}

@Test func withQATheWordsAppearOnlyInTheClosedFields() throws {
    let json = TurnResult.json(finished(), includeText: true)
    let data = try #require(json.data(using: .utf8))
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    var holders: Set<String> = []
    func walk(_ value: Any, path: String) {
        if let text = value as? String, text.contains(sentinel) { holders.insert(path) }
        if let object = value as? [String: Any] {
            for (key, inner) in object { walk(inner, path: path + "." + key) }
        }
        if let list = value as? [Any] { for inner in list { walk(inner, path: path + "[]") } }
    }
    walk(root, path: "")
    expectEq(
        holders,
        [".reply.text", ".tool_calls[].arguments", ".tool_calls[].output", ".status_lines[]", ".receipts[]"],
        "solo los campos de texto cerrados")
}

@Test func anOversizedResultShrinksButStaysValidJSON() throws {
    var record = finished()
    record.toolCalls = (0..<60).map {
        TurnToolCall(
            index: $0, name: "look", arguments: String(repeating: "a", count: 3_000), ok: true, target: "",
            output: String(repeating: "b", count: 3_900), verified: false, band: "act", ownerCheck: "none")
    }
    let json = TurnResult.json(record, includeText: true)
    expect(json.utf8.count <= TurnResult.maxBytes, "cabe bajo el tope del puente")
    let data = try #require(json.data(using: .utf8))
    expect((try? JSONSerialization.jsonObject(with: data)) != nil, "sigue siendo JSON valido")
}

@Test func theRingKeepsFiftyAndNeverMutatesWhatAReaderHolds() {
    var ring = TurnRing()
    for index in 0..<50 { ring = ring.appending(finished("t\(index)")) }
    let held = ring
    let next = ring.appending(finished("t50"))
    expectEq(next.records.count, 50, "51 entran, 50 quedan")
    expect(next.record("t0") == nil, "el mas viejo sale")
    expect(next.record("t50") != nil, "el nuevo entra")
    expect(held.record("t0") != nil, "quien tenia el anillo viejo no lo ve cambiar")
}

@Test func theQAIdleCeilingReplacesTheNormalOneOnlyInQA() {
    expectEq(BridgePolicy.idleTimeout(qa: true, normal: 600), BridgePolicy.idleTimeoutQA, "QA: 60 min")
    expectEq(BridgePolicy.idleTimeout(qa: false, normal: 600), 600, "sin QA: el de siempre")
}

@Test func anAgentTurnPaintsLikeATurnButDoesNotPauseTheBridge() {
    var machine = SessionMachine()
    _ = machine.handle(.agentSubmitted)
    expect(machine.projection.agentTurn, "el turno es del agente")
    expectEq(machine.projection.kind, .processing(.thinking), "pinta como cualquier turno")
    expect(!machine.projection.pausesBridge, "no pausa al puente")
    _ = machine.handle(.typedReplyFinished)
    expect(!machine.projection.agentTurn, "al terminar deja de serlo")
}

@Test func aTurnTypedByTheUserStillPausesTheBridge() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    expect(machine.projection.pausesBridge, "el turno de la usuaria pausa")
}

@Test func aHoldDuringAnAgentTurnStillPausesTheBridge() {
    var projection = SessionProjection()
    projection.agentTurn = true
    projection.kind = .listening
    expect(projection.pausesBridge, "su voz gana sobre el turno del agente")
}

@Test func theOwnerCheckLineNeedsTheSensorAndSurvivesAQuietTurn() {
    var projection = SessionProjection()
    projection.kind = .processing(.thinking)
    projection.agentTurn = true
    projection.ownerCheck = true
    projection.presence = .passive
    let state = IslandState.from(projection, pebbleHidden: true)
    expectEq(state.line, .ownerCheck, "la isla pide el dedo")
    expectEq(state.light, .amber, "y pide atencion")
    expect(!state.line.carriesText, "sin contenido de la usuaria ni del modelo")
}

@Test func theQASessionSheetNamesTheWiderGrant() {
    for language in [AppLanguage.en, .es] {
        expect(BridgeCopy.sheetTitle(language, qa: true) != BridgeCopy.sheetTitle(language), "\(language)")
    }
}
