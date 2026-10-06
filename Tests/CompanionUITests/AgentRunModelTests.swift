import CompanionCore
import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

// Arc's agent-run on the island: each step names what it is doing while it
// runs and what it did once it is done, older steps fold away, and the run's
// loader becomes a check or a cross when it ends.

private let t0 = Date(timeIntervalSince1970: 1_000)

private func step(_ tool: String, _ summary: String = "", done: Bool = false, failed: Bool = false,
                  id: String, start: TimeInterval = 0, end: TimeInterval? = nil) -> JobStepInfo {
    let base = JobTimeline.step(tool, summary)
    return JobStepInfo(tool: tool, label: base.label, done: done || failed, failed: failed, id: id,
                       startedAt: t0.addingTimeInterval(start), finishedAt: end.map { t0.addingTimeInterval($0) })
}

@Test @MainActor func aStepKnowsItsKindByTool() {
    expectEq(AgentRunKind(tool: "Read"), .read, "Read lee")
    expectEq(AgentRunKind(tool: "Grep"), .search, "Grep busca")
    expectEq(AgentRunKind(tool: "Glob"), .search, "Glob busca")
    expectEq(AgentRunKind(tool: "WebSearch"), .web, "WebSearch busca en la web")
    expectEq(AgentRunKind(tool: "WebFetch"), .open, "WebFetch abre")
    expectEq(AgentRunKind(tool: "Write"), .write, "Write escribe")
    expectEq(AgentRunKind(tool: "Edit"), .edit, "Edit edita")
    expectEq(AgentRunKind(tool: "Bash"), .run, "Bash ejecuta")
    expectEq(AgentRunKind(tool: "Task"), .delegate, "Task delega")
    expectEq(AgentRunKind(tool: "TodoWrite"), .plan, "TodoWrite planea")
    expectEq(AgentRunKind(tool: "Misterio"), .other, "desconocida: otra")
}

@Test @MainActor func theTitleIsPresentWhileItRunsAndPastOnceDone() {
    let live = AgentRunModel.steps(steps: [step("Read", "inventario.md", id: "a")], now: t0, language: .es)
    expectEq(live[0].title, "Leyendo inventario.md", "en curso: presente")
    let done = AgentRunModel.steps(steps: [step("Read", "inventario.md", done: true, id: "a", end: 3)],
                                   now: t0, language: .es)
    expectEq(done[0].title, "Leyó inventario.md", "hecho: pasado")
    let failed = AgentRunModel.steps(steps: [step("Read", "inventario.md", failed: true, id: "a", end: 3)],
                                     now: t0, language: .es)
    expectEq(failed[0].title, "No pudo leer inventario.md", "fallo: lo dice")
}

@Test @MainActor func aBareStepUsesTheVerbAlone() {
    let rows = AgentRunModel.steps(steps: [step("Bash", id: "a")], now: t0, language: .es)
    expectEq(rows[0].title, "Ejecutando un comando", "sin objeto: el verbo solo")
}

@Test @MainActor func anUnknownToolKeepsItsCleanedLabel() {
    let rows = AgentRunModel.steps(steps: [step("Misterio", "algo\u{202E}raro", id: "a")], now: t0, language: .es)
    expectEq(rows[0].title, "Misterio: algoraro", "desconocida: la etiqueta limpia")
}

@Test @MainActor func englishTitlesToo() {
    let rows = AgentRunModel.steps(steps: [step("Grep", "idempotencyKey", done: true, id: "a", end: 1)],
                                   now: t0, language: .en)
    expectEq(rows[0].title, "Searched for idempotencyKey", "ingles: pasado")
}

@Test @MainActor func thinkingStepsStayOffTheRail() {
    let rows = AgentRunModel.steps(steps: [step(JobSteps.Thinking.tool, "x", id: "t"), step("Read", "a", id: "r")],
                                   now: t0, language: .es)
    expectEq(rows.map(\.id), ["r"], "pensar no ocupa fila")
}

@Test @MainActor func aStepCarriesItsStatusAndTime() {
    let rows = AgentRunModel.steps(steps: [
        step("Bash", "ls", done: true, id: "a", end: 12),
        step("Read", "b.md", failed: true, id: "b", start: 12, end: 77),
        step("Write", "c.md", id: "c", start: 77),
    ], now: t0.addingTimeInterval(80), language: .es)
    expectEq(rows.map(\.status), [.done, .failed, .active], "estados")
    expectEq(rows.map(\.duration), ["12s", "1m 05s", "3s"], "duraciones")
    expectEq(rows.map(\.icon), ["terminal", "doc.text", "pencil.line"], "iconos de la herramienta")
}

// The rail fills down to a node once the step above it is done.
@Test @MainActor func theRailFillsBehindFinishedSteps() {
    let rows = AgentRunModel.steps(steps: [
        step("Bash", done: true, id: "a", end: 1), step("Read", id: "b", start: 1),
    ], now: t0.addingTimeInterval(2), language: .es)
    expectEq(rows.map(\.railFill), [1, 0], "lleno tras lo hecho, vacio en lo vivo")
}

@Test @MainActor func olderStepsFoldAwayAtRest() {
    let rows = (0..<7).map {
        AgentRunStep(id: "s\($0)", kind: .run, title: "p\($0)", icon: "terminal",
                     status: $0 < 6 ? .done : .active, duration: nil)
    }
    let rest = AgentRunModel.visible(rows, expanded: false)
    expectEq(rest.folded, 4, "en reposo: se pliegan los viejos")
    expectEq(rest.shown.map(\.id), ["s4", "s5", "s6"], "en reposo: los ultimos tres")
    let open = AgentRunModel.visible(rows, expanded: true)
    expectEq(open.folded, 0, "abierto: nada plegado")
    expectEq(open.shown.count, 7, "abierto: todos")
    let few = AgentRunModel.visible(Array(rows.prefix(2)), expanded: false)
    expectEq(few.folded, 0, "pocos: nada que plegar")
}

@Test @MainActor func theRunLoaderEndsOnACheckOrACross() {
    expectEq(AgentRunModel.status([step("Bash", id: "a")]), .loading, "algo vivo: cargando")
    expectEq(AgentRunModel.status([]), .loading, "sin pasos aun: cargando")
    expectEq(AgentRunModel.status([step("Bash", done: true, id: "a", end: 1)]), .success, "todo hecho: check")
    expectEq(AgentRunModel.status([step("Bash", failed: true, id: "a", end: 1)]), .error, "el ultimo fallo: cruz")
}


// The rail replaced the agent bars: a delegated subagent still shows while it
// runs, and folding the old steps never folds away the live one.
@Test @MainActor func aLiveDelegateStaysInViewWhenOldStepsFold() {
    let done = (0..<5).map { step("Read", "f\($0).md", done: true, id: "r\($0)", start: Double($0), end: Double($0) + 1) }
    let live = step("Task", "revisar el plan", id: "t", start: 6)
    let rows = AgentRunModel.steps(steps: done + [live], now: t0.addingTimeInterval(8), language: .es)
    let rest = AgentRunModel.visible(rows, expanded: false)
    expect(rest.folded > 0, "los viejos se pliegan")
    let shownLive = rest.shown.first { $0.id == "t" }
    expectEq(shownLive?.kind, .delegate, "el subagente se ve")
    expectEq(shownLive?.status, .active, "y sigue vivo")
}

// QA review: parallel tools finish around a live one; folding the old steps
// must never fold the step that is still running.
@Test @MainActor func aLiveStepAmongNewerFinishedOnesNeverFolds() {
    let rows = (0..<9).map { i in
        AgentRunStep(id: "s\(i)", kind: i == 5 ? .delegate : .read, title: "p\(i)", icon: "doc.text",
                     status: i == 5 ? .active : .done, duration: nil)
    }
    let rest = AgentRunModel.visible(rows, expanded: false)
    expect(rest.shown.contains { $0.id == "s5" }, "el vivo se ve")
    expectEq(rest.shown.map(\.id), ["s5", "s6", "s7", "s8"], "el vivo y los tres ultimos, en orden")
    expectEq(rest.folded, 5, "plegados: solo los que no se ven")
}

@Test @MainActor func threeStepsNeverFoldAndFourFoldOne() {
    let rows = (0..<4).map {
        AgentRunStep(id: "s\($0)", kind: .run, title: "p", icon: "terminal", status: .done, duration: nil)
    }
    expectEq(AgentRunModel.visible(Array(rows.prefix(3)), expanded: false).folded, 0, "tres: nada plegado")
    expectEq(AgentRunModel.visible(rows, expanded: false).folded, 1, "cuatro: uno plegado")
}
