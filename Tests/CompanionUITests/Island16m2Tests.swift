import CompanionCore
import CompanionTestKit
import CompanionUI
import Foundation
import Testing

// Wave 16m-2: the working states. The runcard needs steps that KNOW whether
// they finished and how; the reel needs the apps a turn touched to survive
// past `parentActed`. Both are projection facts, pinned here before any view.

@Test func island16m2MachineTests() {
    testStepFinishedMarksItsStep()
    testStepFailureSurvivesOnTheStep()
    testReelAccumulatesAcrossRounds()
    testReelShowsTheAppTouchedLast()
    testARepeatAtTheCapEvictsNothing()
    testOneRoundKeepsItsOrderAndBlanksStayOut()
    testReelIsCappedPerTurn()
    testReelClearsWithTheNextTurn()
}

@Test @MainActor func island16m2MetricsTests() {
    testWorkMeasuresMatchIncredible()
    testAgentsAreTheLiveTaskSteps()
}

@MainActor func testWorkMeasuresMatchIncredible() {
    expectEq([WorkStateMetrics.runMinWidth, WorkStateMetrics.runMaxWidth],
             [320, 420], "16m-2 runcard: 320-420 de ancho")
    expectEq([WorkStateMetrics.runPaddingTop, WorkStateMetrics.runPaddingX,
              WorkStateMetrics.runPaddingBottom], [14, 16, 12], "16m-2 runcard: 14/16/12")
    expectEq(WorkStateMetrics.runRadius, 20, "16m-2 runcard: radio 20")
    expectEq([WorkStateMetrics.runShadowY, WorkStateMetrics.runShadowAlpha],
             [18, 0.32], "16m-2 runcard: sombra 0 18 48 al 32 %")
    expectEq([WorkStateMetrics.stepPaddingY, WorkStateMetrics.stepPaddingX,
              WorkStateMetrics.stepGap], [5, 2, 2], "16m-2 paso: 5 × 2, gap 2")
    expectEq(WorkStateMetrics.reelHeight, 26, "16m-2 carrete: banda de 26")
    expectEq([WorkStateMetrics.transcriptSize, WorkStateMetrics.transcriptLeading],
             [14, 1.5], "16m-2 transcripción: 14 con 1.5")
    expectEq([WorkStateMetrics.transcriptLive, WorkStateMetrics.transcriptFixed],
             [0.72, 0.94], "16m-2 transcripción: 72 % viva, 94 % fija")
    expectEq(WorkStateMetrics.agentGap, 10, "16m-2 agentes: gap 10")
}

@MainActor func testAgentsAreTheLiveTaskSteps() {
    let steps = [
        JobStepInfo(tool: "Task", label: "Task: revisar", done: true),
        JobStepInfo(tool: "Task", label: "Task: buscar"),
        JobStepInfo(tool: "Bash", label: "Bash: ls"),
    ]
    expectEq(WorkStateMetrics.agents(steps).map(\.label), ["Task: buscar"],
             "16m-2 agentes: solo los Task que siguen fuera")
}

func testStepFinishedMarksItsStep() {
    var machine = SessionMachine()
    _ = machine.handle(.job(.started(goal: "ordenar fotos")))
    _ = machine.handle(.job(.stepStarted(tool: "Bash", summary: "ls")))
    _ = machine.handle(.job(.stepStarted(tool: "Write", summary: "plan.md")))
    _ = machine.handle(.job(.stepFinished(tool: "Bash", ok: true)))
    let steps = machine.projection.job?.steps ?? []
    expectEq(steps.map(\.done), [true, false], "16m-2: termina el paso de su tool, no el último")
    expectEq(steps.map(\.failed), [false, false], "16m-2: ok no marca fallo")
}

func testStepFailureSurvivesOnTheStep() {
    var machine = SessionMachine()
    _ = machine.handle(.job(.started(goal: "")))
    _ = machine.handle(.job(.stepStarted(tool: "WebFetch", summary: "docs")))
    _ = machine.handle(.job(.stepFinished(tool: "WebFetch", ok: false)))
    // The same tool again: the finished one stays finished, the new one runs.
    _ = machine.handle(.job(.stepStarted(tool: "WebFetch", summary: "retry")))
    _ = machine.handle(.job(.stepFinished(tool: "WebFetch", ok: true)))
    let steps = machine.projection.job?.steps ?? []
    expectEq(steps.map(\.failed), [true, false], "16m-2: el fallo queda en SU paso")
    expectEq(steps.map(\.done), [true, true], "16m-2: ambos terminados")
}

func testReelAccumulatesAcrossRounds() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.parentActing(targets: ["Slack"]))
    _ = machine.handle(.parentActed)
    _ = machine.handle(.parentActing(targets: ["Safari", "Slack"]))
    _ = machine.handle(.parentActed)
    // K8: the reel shows the app touched LAST, so a repeat moves to the end.
    expectEq(machine.projection.touched, ["Safari", "Slack"],
             "16m-2: el carrete acumula sin duplicar, en orden de ultimo toque")
    expectEq(machine.projection.targets, [], "16m-2: targets sigue siendo solo la ronda viva")
}

func testReelShowsTheAppTouchedLast() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    for app in ["Safari", "Notas", "Safari"] {
        _ = machine.handle(.parentActing(targets: [app]))
        _ = machine.handle(.parentActed)
    }
    expectEq(machine.projection.touched, ["Notas", "Safari"], "K8: volver a Safari lo pone al final")
    expectEq(machine.projection.touched.last, "Safari", "K8: el carrete muestra la app donde actua")
}

func testARepeatAtTheCapEvictsNothing() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    let apps = (0 ..< SessionMachine.touchedCap).map { "app-\($0)" }
    for app in apps {
        _ = machine.handle(.parentActing(targets: [app]))
        _ = machine.handle(.parentActed)
    }
    _ = machine.handle(.parentActing(targets: ["app-0"]))
    expectEq(machine.projection.touched, Array(apps.dropFirst()) + ["app-0"],
             "K8: volver a la mas vieja con el carrete lleno la mueve al final sin sacar a nadie")
    _ = machine.handle(.parentActing(targets: ["app-0"]))
    expectEq(machine.projection.touched, Array(apps.dropFirst()) + ["app-0"], "K8: repetir la ultima no cambia nada")
}

func testOneRoundKeepsItsOrderAndBlanksStayOut() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.parentActing(targets: ["A", "B", "A"]))
    expectEq(machine.projection.touched, ["B", "A"], "K8: un repetido dentro de la ronda queda al final")
    _ = machine.handle(.parentActing(targets: ["", "X", "Y"]))
    expectEq(machine.projection.touched, ["B", "A", "X", "Y"], "K8: dos nuevas conservan su orden; el vacio no entra")
    _ = machine.handle(.parentActing(targets: [""]))
    expectEq(machine.projection.touched.last, "Y", "K8: una ronda sin nombre no reordena")
}

func testReelClearsWithTheNextTurn() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.parentActing(targets: ["Slack"]))
    _ = machine.handle(.parentActed)
    _ = machine.handle(.typedSubmitted)
    expectEq(machine.projection.touched, [], "16m-2: un turno nuevo estrena carrete")

    var held = SessionMachine()
    _ = held.handle(.parentActing(targets: ["Notas"]))
    _ = held.handle(.parentActed)
    _ = held.handle(.pressed)
    expectEq(held.projection.touched, [], "16m-2: el hold tambien lo estrena")

    // Review 16m H1: the classic hold arms through pressedProvisionally and
    // the voice runtime through its listening snapshot — every door in.
    var provisional = SessionMachine()
    _ = provisional.handle(.parentActing(targets: ["Notas"]))
    _ = provisional.handle(.parentActed)
    _ = provisional.handle(.pressedProvisionally)
    expectEq(provisional.projection.touched, [], "16m-2: el hold provisional tambien")

    var voiced = SessionMachine()
    _ = voiced.handle(.parentActing(targets: ["Notas"]))
    _ = voiced.handle(.parentActed)
    _ = voiced.handle(.voice(TurnSnapshot(state: .listening)))
    expectEq(voiced.projection.touched, [], "16m-2: la voz al escuchar tambien")
}

func testReelIsCappedPerTurn() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    for i in 0 ..< 30 {
        _ = machine.handle(.parentActing(targets: ["app-\(i)"]))
        _ = machine.handle(.parentActed)
    }
    // Security review 16m: a looping turn must not grow the reel without
    // bound; the newest touches win, the oldest fall off.
    expectEq(machine.projection.touched.count, SessionMachine.touchedCap,
             "16m-2: el carrete tiene tope")
    expectEq(machine.projection.touched.last, "app-29", "16m-2: lo nuevo entra")
    expectEq(machine.projection.touched.first, "app-\(30 - SessionMachine.touchedCap)", "16m-2: sale lo mas viejo")
}
