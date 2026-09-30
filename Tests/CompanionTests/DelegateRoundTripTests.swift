import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

@Test @MainActor func delegateRoundTripTests() async {
    await testTheDelegateCallAndItsResultTravelAsAPair()
    await testTheReportNeverEntersHistoryAsAssistant()
    await testTheThreadStillShowsTheWholeReport()
    await testNoToolTurnTravelsWithoutItsID()
    await testOrdinaryMessagesAreUnchanged()
}

@MainActor private func delegated(
    result: String, preface: String = "Voy a mirar."
) async -> ChatViewModel {
    let handoff = Handoff(goal: "buscar la carpeta", context: "")
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default)
    vm.onAppear()
    await vm.runJob(
        preface: preface, handoff: handoff,
        submitter: ReportSubmitter(output: result))
    return vm
}

@MainActor func testTheDelegateCallAndItsResultTravelAsAPair() async {
    let vm = await delegated(result: "# Informe\n\nLa carpeta existe.")
    let turns = vm.historyForTests()

    guard let call = turns.first(where: { !$0.toolCalls.isEmpty }) else {
        expect(false, "la llamada a delegate sobrevive en el historial")
        return
    }
    expectEq(call.role, .assistant, "quien pide la tool es el asistente")
    expectEq(call.toolCalls.first?.name, "delegate", "y la tool es delegate")

    guard let answer = turns.first(where: { $0.role == .tool }) else {
        expect(false, "el resultado vuelve como turno de tool")
        return
    }
    expectEq(answer.toolCallID, call.toolCalls.first?.id,
             "atado a la llamada que lo provoco: la API lo exige")
}

@MainActor func testTheReportNeverEntersHistoryAsAssistant() async {
    // El defecto que motivo la wave: el modelo se creia autor del informe y
    // empezaba a comportarse como quien acaba de hacer el trabajo.
    let report = "# Resultado\n\nLa carpeta se llama SoftwareDevProjects."
    let vm = await delegated(result: report)
    let assistantText = vm.historyForTests()
        .filter { $0.role == .assistant }.map(\.content).joined()
    expect(!assistantText.contains("SoftwareDevProjects"),
           "el informe no se le atribuye al modelo de charla")
}

@MainActor func testTheThreadStillShowsTheWholeReport() async {
    // Esta wave no quita nada de la pantalla.
    let report = "# Resultado\n\nLa carpeta se llama SoftwareDevProjects."
    let vm = await delegated(result: report)
    expect(vm.messages.contains { $0.text == report },
           "el hilo sigue mostrando el informe completo")
}

@MainActor func testNoToolTurnTravelsWithoutItsID() async {
    let vm = await delegated(result: "listo")
    for turn in vm.historyForTests() where turn.role == .tool {
        expect(turn.toolCallID != nil,
               "un turno de tool sin id es un request que el proveedor rechaza")
    }
}

@MainActor func testOrdinaryMessagesAreUnchanged() async {
    // La regresion posible queda acotada al camino de encargos.
    let vm = await delegated(result: "listo")
    let user = vm.historyForTests().filter { $0.role == .user }
    expect(user.allSatisfy { $0.toolCalls.isEmpty && $0.toolCallID == nil },
           "un mensaje normal viaja como siempre")
}

struct ReportSubmitter: JobSubmitter {
    let output: String
    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        events.finish()
        return JobResult(output: output, isError: false)
    }
    func cancel() async {}
    func cancel(job id: JobID) async { await cancel() }
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}

@Test @MainActor func toolTurnWindowingTests() {
    testAToolTurnWhoseCallWasCutAwayIsDropped()
    testAPairInsideTheWindowSurvivesWhole()
}

@MainActor func testAToolTurnWhoseCallWasCutAwayIsDropped() {
    // La ventana puede caer entre la llamada y su respuesta. Un turno de tool
    // sin su llamada no es inutil: el proveedor rechaza la peticion ENTERA,
    // asi que el turno siguiente a una conversacion larga fallaria en seco.
    let orphan = Turn(role: .tool, content: "el informe", toolCallID: "abc")
    let after = Turn(role: .user, content: "gracias")
    let kept = ChatViewModel.dropOrphanedToolTurns([orphan, after])
    expectEq(kept.map(\.role), [.user], "el huerfano se cae, el resto sigue")
}

@MainActor func testAPairInsideTheWindowSurvivesWhole() {
    let call = Turn(
        role: .assistant, content: "voy",
        toolCalls: [ToolCallRef(id: "abc", name: "delegate", arguments: "{}")])
    let answer = Turn(role: .tool, content: "el informe", toolCallID: "abc")
    let kept = ChatViewModel.dropOrphanedToolTurns([call, answer])
    expectEq(kept.count, 2, "una pareja completa no se toca")
}

@Test @MainActor func chatCardsStayOutOfMemoryTests() async {
    // Ahora que la charla tambien pinta tarjetas, su propio JSON entraria al
    // historial por el camino ordinario, que no pasaba por ningun filtro.
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default)
    vm.onAppear()
    await vm.appendAssistant("""
    Ahí está.

    ```companion:locations
    {"title":"X","locations":[{"name":"Soumaya","lat":19.44,"lng":-99.20}]}
    ```
    """)
    let history = vm.historyForTests().map(\.content).joined()
    expect(!history.contains("19.44"),
           "la tarjeta de la charla tampoco entra en la memoria")
    expect(vm.messages.contains { $0.text.contains("19.44") },
           "pero el hilo sigue teniendo con que pintarla")
}
