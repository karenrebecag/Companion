import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// La tarjeta del encargo: paso vivo y duración. Hasta ahora los pasos caían
// como líneas de status sueltas en el hilo — el mismo mecanismo que el chat,
// pero sin decir cuánto llevaba ni cuál era el paso de AHORA.

@Test @MainActor func jobTimelineTests() async {
    testStepSummaryCounts()
    testWorkedDuration()
    testIconPerTool()
    await testStepsBuildTheCardNotStatusLines()
    await testCardClosesWhenTheResultLands()
}

/// El chip al estilo Grok sale de los pasos, no de una invención.
@MainActor func testStepSummaryCounts() {
    let steps = [
        JobStepInfo(tool: "WebSearch", label: "WebSearch: vuelos"),
        JobStepInfo(tool: "WebSearch", label: "WebSearch: hoteles"),
        JobStepInfo(tool: "Write", label: "Write: /tmp/plan.md"),
        JobStepInfo(tool: "Read", label: "Read: /tmp/plan.md"),
        JobStepInfo(tool: "Bash", label: "Bash: ls"),
    ]
    expectEq(JobSteps.summary(steps), "2 searches · 1 file · 1 command",
             "resumen: cuenta por tipo, los archivos únicos una vez")
    expectEq(JobSteps.summary([]), nil,
             "resumen: sin pasos no hay chip que enseñar")
    expectEq(JobSteps.summary([JobStepInfo(tool: "WebSearch", label: "x")]),
             "1 search", "resumen: el singular no dice «1 searches»")
    expectEq(JobSteps.summary(steps, .es), "2 búsquedas · 1 archivo · 1 comando",
             "resumen: la traducción conserva el copy original")
    expectEq(JobSteps.files(steps), ["/tmp/plan.md"],
             "archivos: la misma ruta tocada dos veces es una")
}

/// Segundos abajo, minutos arriba: nadie lee "Trabajó 102 s".
@MainActor func testWorkedDuration() {
    expectEq(JobSteps.worked(47), "Worked 47 s", "duración: segundos sueltos")
    expectEq(JobSteps.worked(102), "Worked 1:42", "duración: minutos con cero")
    expectEq(JobSteps.worked(102, .es), "Trabajó 1:42", "duración: en español")
    expectEq(JobSteps.worked(0), "Worked 0 s", "duración: recién empezado")
}

@MainActor func testIconPerTool() {
    expectEq(JobSteps.icon(for: "WebSearch"), "globe", "icono: búsqueda")
    expectEq(JobSteps.icon(for: "Thinking"), "lightbulb", "icono: pensamiento")
    expectEq(JobSteps.icon(for: "HerramientaRara"), "gearshape",
             "icono: una herramienta desconocida no deja el hueco vacío")
}

/// Los pasos alimentan la tarjeta; el hilo deja de llenarse de líneas.
@MainActor func testStepsBuildTheCardNotStatusLines() async {
    let model = makeTimelineModel()
    model.startJob(goal: "crear prueba1.md")
    model.receiveJobEvent(.stepStarted(tool: "Write", summary: "prueba1.md"))
    model.receiveJobEvent(.stepFinished(tool: "Write", ok: true))
    model.receiveJobEvent(.thought("Reviso que el escritorio exista"))

    let job = model.job
    expectEq(job?.goal, "crear prueba1.md", "tarjeta: el encargo tiene nombre")
    expectEq(job?.steps.count, 2,
             "tarjeta: un paso por herramienta y uno por pensamiento")
    expectEq(job?.steps.last?.tool, "Thinking",
             "tarjeta: el pensamiento es el paso vivo")
    expect(model.messages.isEmpty,
           "tarjeta: los pasos ya no ensucian el hilo con status sueltos")
}

/// Cuando llega el resultado, la tarjeta viva se apaga: el informe manda.
@MainActor func testCardClosesWhenTheResultLands() async {
    let model = makeTimelineModel()
    model.startJob(goal: "algo")
    model.receiveJobEvent(.stepStarted(tool: "Bash", summary: "ls"))
    expect(model.job != nil, "tarjeta: viva mientras trabaja")

    await model.appendAssistant("# Listo\nya está")
    expect(model.job == nil, "tarjeta: el resultado la cierra")

    // Y un fallo también: nada de tarjetas colgadas para siempre.
    model.startJob(goal: "lo imposible")
    model.receiveJobEvent(.stepStarted(tool: "Bash", summary: "ls"))
    await model.appendStatus("El encargo «lo imposible» no se pudo completar.")
    expect(model.job == nil, "tarjeta: un fallo también la cierra")
}

@MainActor private func makeTimelineModel() -> ChatViewModel {
    primed(chat: FakeChatProvider())
}
