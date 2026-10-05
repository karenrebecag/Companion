import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// 5a: a step's real start, end and fate. Each case pins one way the card's
// data used to lie (done on arrival, first tool_use only, pairing by name).

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000)
    func now() -> Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private func machine(_ clock: TestClock) -> SessionMachine {
    SessionMachine(clock: { clock.now() })
}

@Test @MainActor func twoToolUsesInOneMessageAreTwoEvents() {
    let events = AgentStreamCodec.events("""
    {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"a.md"}},{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"ls"}}]}}
    """)
    expectEq(events, [
        .toolUse(id: "t1", name: "Read", detail: "a.md"),
        .toolUse(id: "t2", name: "Bash", detail: "ls"),
    ], "un mensaje con dos tool_use emite los dos, con su id")
}

@Test @MainActor func toolResultCarriesIdAndError() {
    let events = AgentStreamCodec.events("""
    {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"},{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"boom"}]}}
    """)
    expectEq(events, [
        .toolResult(id: "t1", isError: false),
        .toolResult(id: "t2", isError: true),
    ], "tool_result: id y is_error por bloque")
    expectEq(AgentStreamCodec.events(
        #"{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}"#),
             [], "tool_result sin tool_use_id no se puede emparejar: se ignora")
    expectEq(AgentStreamCodec.events(
        #"{"type":"user","message":{"content":[{"type":"text","text":"hola"}]}}"#),
             [], "un turno de usuario sin resultados no emite nada")
}

@Test @MainActor func toolUseKeepsToolBeatingThoughtAndNoId() {
    let both = AgentStreamCodec.events("""
    {"type":"assistant","message":{"content":[{"type":"thinking","thinking":"pienso"},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
    """)
    expectEq(both, [.toolUse(id: nil, name: "Bash", detail: "ls")],
             "sin id en el stream el paso nace sin id, y la accion manda sobre el pensamiento")
}

@Test @MainActor func stepStartsOpenAndClosesWithItsTimes() {
    let clock = TestClock()
    var m = machine(clock)
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls", id: "a")))
    var step = m.projection.job?.steps.first
    expectEq(step?.id, "a", "el paso lleva el id del stream")
    expectEq(step?.startedAt, Date(timeIntervalSince1970: 1_000), "inicio con el reloj inyectado")
    expect(step?.finishedAt == nil && step?.done == false, "abierto hasta que llegue su resultado")
    clock.advance(12)
    _ = m.handle(.job(.stepFinished(tool: "Bash", ok: true, id: "a")))
    step = m.projection.job?.steps.first
    expectEq(step?.finishedAt, Date(timeIntervalSince1970: 1_012), "fin con el reloj inyectado")
    expect(step?.done == true && step?.failed == false, "cerrado bien")
}

@Test @MainActor func failedResultMarksTheStepFailed() {
    let clock = TestClock()
    var m = machine(clock)
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls", id: "a")))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "rm", id: "b")))
    _ = m.handle(.job(.stepFinished(tool: "Bash", ok: false, id: "b")))
    let steps = m.projection.job?.steps ?? []
    expectEq(steps.map(\.failed), [false, true], "is_error marca solo la fila b como fallida")
    expect(steps.first?.done == false, "a sigue abierta")
}

@Test @MainActor func aThoughtIsInstantAndAlreadyDone() {
    let clock = TestClock()
    var m = machine(clock)
    _ = m.handle(.job(.started(goal: "x")))
    clock.advance(5)
    _ = m.handle(.job(.thought("pienso")))
    let step = m.projection.job?.steps.first
    expectEq(step?.startedAt, Date(timeIntervalSince1970: 1_005), "el pensamiento nace con el reloj inyectado")
    expectEq(step?.finishedAt, step?.startedAt, "un pensamiento es instantaneo: fin == inicio")
    expect(step?.done == true && step?.failed == false, "nace cerrado, no fallido")
    expect(step?.id.isEmpty == false, "lleva id")
}

@Test @MainActor func jobStartUsesTheInjectedClock() {
    let clock = TestClock()
    var m = machine(clock)
    _ = m.handle(.job(.started(goal: "x")))
    expectEq(m.projection.job?.startedAt, Date(timeIntervalSince1970: 1_000), "started: reloj inyectado")

    var voice = machine(clock)
    clock.advance(7)
    _ = voice.handle(.job(.stepStarted(tool: "Bash", summary: "ls", id: "a")))
    expectEq(voice.projection.job?.startedAt, Date(timeIntervalSince1970: 1_007),
             "un paso que abre un trabajo de voz antes de su nombre usa el reloj inyectado")
}

@Test @MainActor func aMintedIdNeverMatchesAProducerId() {
    let clock = TestClock()
    var m = machine(clock)
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls", id: nil)))
    let minted = m.projection.job?.steps.first?.id ?? ""
    _ = m.handle(.job(.stepFinished(tool: "Bash", ok: true, id: minted)))
    expect(m.projection.job?.steps.first?.done == false,
           "un id del stream igual al minteado no cierra un paso sin id")
}

@Test @MainActor func anUnknownIdLeavesAnUntaggedStepOpen() {
    let clock = TestClock()
    var m = machine(clock)
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls", id: nil)))
    _ = m.handle(.job(.stepFinished(tool: "Bash", ok: true, id: "x")))
    expect(m.projection.job?.steps.first?.done == false, "un id desconocido se ignora; el retiro del trabajo lo limpia")
}

@Test @MainActor func aSecondFinishForAClosedIdIsANoOp() {
    let clock = TestClock()
    var m = machine(clock)
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls", id: "a")))
    clock.advance(2)
    _ = m.handle(.job(.stepFinished(tool: "Bash", ok: true, id: "a")))
    clock.advance(2)
    _ = m.handle(.job(.stepFinished(tool: "Bash", ok: false, id: "a")))
    let step = m.projection.job?.steps.first
    expect(step?.failed == false, "el segundo fin no reescribe el resultado")
    expectEq(step?.finishedAt, Date(timeIntervalSince1970: 1_002), "ni el tiempo de fin")
}

@Test @MainActor func finishWithoutStartIsIgnored() {
    let clock = TestClock()
    var m = machine(clock)
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls", id: "a")))
    _ = m.handle(.job(.stepFinished(tool: "Bash", ok: true, id: "zzz")))
    let step = m.projection.job?.steps.first
    expect(step?.done == false, "un fin con id desconocido no cierra otro paso")
    expectEq(m.projection.job?.steps.count, 1, "ni crea uno")
}

@Test @MainActor func parallelCallsOfOneToolCloseEachOwnRow() {
    let clock = TestClock()
    var m = machine(clock)
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "one", id: "a")))
    clock.advance(1)
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "two", id: "b")))
    clock.advance(1)
    _ = m.handle(.job(.stepFinished(tool: "Bash", ok: false, id: "b")))
    var steps = m.projection.job?.steps ?? []
    expectEq(steps.map(\.done), [false, true], "termina la fila b, no la mas antigua de la tool")
    expectEq(steps.map(\.failed), [false, true], "el fallo queda en la fila b")
    clock.advance(1)
    _ = m.handle(.job(.stepFinished(tool: "Bash", ok: true, id: "a")))
    steps = m.projection.job?.steps ?? []
    expectEq(steps.map(\.done), [true, true], "luego cierra a")
    expectEq(steps[1].startedAt, Date(timeIntervalSince1970: 1_001), "b empezo un segundo despues de a")
    expectEq(steps[0].finishedAt, Date(timeIntervalSince1970: 1_003), "tiempo propio de a")
    expectEq(steps[1].finishedAt, Date(timeIntervalSince1970: 1_002), "tiempo propio de b")
}

@Test @MainActor func nativeSummaryIsReadable() {
    expectEq(AgentStreamCodec.toolDetail(fromInputJSON: #"{"path":"/tmp/a.md"}"#),
             "/tmp/a.md", "con argumento, el argumento")
    expectEq(AgentStreamCodec.toolDetail(fromInputJSON: "{}"),
             "", "sin argumento, vacio: la etiqueta no repite la tool")
    expectEq(AgentStreamCodec.toolDetail(fromInputJSON: "no json"),
             "", "argumentos rotos no truenan")
    expectEq(JobTimeline.step("run_shell", "").label, "run_shell", "la etiqueta sin argumento es la tool sola")
}
