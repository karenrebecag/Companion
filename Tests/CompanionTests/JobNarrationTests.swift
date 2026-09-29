import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// La voz narraba encargos que no podía leer. El anuncio decía "el resultado
// ya está en pantalla; cuéntalo en una frase" y jamás le pasaba el resultado:
// el modelo rellenaba con lo más plausible — que había salido bien — mientras
// el especialista reportaba lo contrario en el hilo. Prueba manual de Karen,
// 2026-08-22: "the file is right there on your desktop" sobre un archivo que
// nunca existió.

@Test @MainActor func jobNarrationTests() async {
    await pinLanguage {
        testResultSummaryTakesTheFirstLine()
        testTheDoneAnnouncementAcknowledgesWithoutReadingBack()
        testFailureAnnouncementCarriesTheReason()
        await testBridgeAcknowledgesWithoutRereadingTheResult()
        await testTheJobLeavesARecordInTheThread()
        await testVoiceJobsRecordTheirGoalToo()
        await testAnnouncementFollowsTheLanguage()
    }
}

/// El anuncio es un system item para el modelo: en español tiene que llegar
/// en español, o la sesión razona en dos idiomas a la vez.
@MainActor func testAnnouncementFollowsTheLanguage() async {
    let announced = TextBox()
    await VoiceJobBridge.run(
        Handoff(goal: "crear test.md", context: ""),
        jobs: FixedSubmitter(result: JobResult(output: "Hecho", isError: false)),
        thread: ScriptedThread(),
        announce: { announced.append($0.instruction) },
        language: .es)
    expect(announced.all.joined().contains("en pantalla"),
           "idioma: el anuncio viaja en el idioma de la sesión")
}

/// El rol del especialista le exige abrir con un resumen de una línea; esto
/// es esa línea, sin markdown y sin novela.
@MainActor func testResultSummaryTakesTheFirstLine() {
    expectEq(Escalation.resultSummary("# Listo\n\nDetalle largo\nMás"),
             "Listo", "resumen: primera línea útil, sin almohadilla")
    expectEq(Escalation.resultSummary("\n\n  Creé el archivo.  \n resto"),
             "Creé el archivo.", "resumen: salta líneas vacías y recorta")
    expectEq(Escalation.resultSummary(""), "",
             "resumen: sin salida no se inventa una")
    let long = String(repeating: "a", count: 400)
    expect(Escalation.resultSummary(long).count <= 200,
           "resumen: una frase, no un informe leído en voz alta")
}

/// El exito ya no se relee: el texto del especialista es el mensaje del hilo
/// y la voz solo acusa. Lo que NO cambia es la prohibición de adornar, que es
/// lo que impedía inventar un final feliz.
@MainActor func testTheDoneAnnouncementAcknowledgesWithoutReadingBack() {
    let text = Escalation.jobDoneAnnouncement("create test.md")
    expect(text.contains("create test.md"),
           "anuncio: se nombra el encargo que terminó")
    expect(text.lowercased().contains("on screen"),
           "anuncio: se remite a la pantalla, que es donde está el resultado")
    expect(text.lowercased().contains("do not add"),
           "anuncio: se le prohíbe explícitamente adornar")
}

@MainActor func testFailureAnnouncementCarriesTheReason() {
    let text = Escalation.jobFailedAnnouncement(
        "create test.md", reason: "the specialist never started")
    expect(text.contains("the specialist never started"),
           "fallo: la voz dice el motivo real, no un genérico")
}

/// El circuito completo. La garantía de la Wave 8 sigue en pie por otra vía:
/// cuál de los dos finales ocurrió lo decide el especialista, no el modelo.
/// Lo que ya no pasa es que el resultado se lea dos veces.
@MainActor func testBridgeAcknowledgesWithoutRereadingTheResult() async {
    let announced = TextBox()
    let thread = ScriptedThread()
    let output = "Cree el archivo en el escritorio.\n\nDetalle…"
    await VoiceJobBridge.run(
        Handoff(goal: "create test.md", context: ""),
        jobs: FixedSubmitter(result: JobResult(output: output, isError: false)),
        thread: thread,
        announce: { announced.append($0.instruction) })

    expectEq(thread.turns.last?.content, output,
             "circuito: el texto del especialista es el mensaje, entero")
    let text = announced.all.joined(separator: " ")
    expect(!text.contains("Cree el archivo"),
           "circuito: la voz no repite lo que ya está en pantalla")
    expect(text.contains("create test.md"),
           "circuito: pero sí sabe qué encargo terminó")
}

/// La tarjeta viva desaparece al terminar; sin registro no se puede saber
/// qué se delegó. Regresión introducida al sustituir la línea de status por
/// la tarjeta (Wave 8).
@MainActor func testTheJobLeavesARecordInTheThread() async {
    let model = primed(chat: FakeChatProvider())
    let id = model.startJob(goal: "create test.md")
    model.receiveJobEvent(.stepStarted(tool: "WebSearch", summary: "x"), from: id)
    model.finishJob(ok: true, id: id)

    expect(model.job == nil, "registro: la tarjeta viva se apaga")
    let statuses = model.messages.filter { $0.isStatus }.map(\.text)
    expect(statuses.contains { $0.contains("create test.md") },
           "registro: el hilo conserva QUÉ se delegó")
    expect(statuses.contains { $0.contains("1 search") },
           "registro: y el resumen de lo que hizo")
}

/// El encargo por voz llega solo como eventos: su objetivo tiene que viajar
/// por la misma costura o el registro queda anónimo.
@MainActor func testVoiceJobsRecordTheirGoalToo() async {
    let model = primed(chat: FakeChatProvider())
    let voice = JobID("voz")
    model.receive(.job(.started(goal: "buscar vuelos"), from: voice))
    expectEq(model.job?.goal, "buscar vuelos",
             "costura: el goal del encargo por voz llega al hilo")
    // Review 16h-2 round 3: its own end records it, not a reply landing.
    model.receive(.jobFinished(ok: true, from: voice))
    expect(model.messages.contains { $0.isStatus && $0.text.contains("buscar vuelos") },
           "costura: y queda registrado al cerrar")
}
