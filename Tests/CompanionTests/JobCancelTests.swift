import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

@Test @MainActor func jobCancelTests() async {
    await testStoppingReachesTheRunner()
    await testAStoppedJobDeliversNoResult()
    await testWhatWasDoneIsKeptAndSaid()
    await testTheCardCloses()
    await testStoppingWithNoJobIsHarmless()
}

final class WatchfulSubmitter: JobSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    private var _released: (() -> Void)?
    let output: String

    init(output: String = "informe") { self.output = output }

    var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }; return _cancelled
    }

    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        events.yield(.stepStarted(tool: "run_shell", summary: "df -h"))
        // Espera como un encargo de verdad, pero ACOTADA: un test que no lo
        // cancela dejaba esta tarea girando el resto de la suite y volvia
        // intermitentes a los tests que dependen de temporizadores.
        for _ in 0 ..< 200 where !cancelled {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw CancellationError()
    }

    func cancel() async { markCancelled() }

    private func markCancelled() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = true
    }
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}

@MainActor private func running(_ submitter: WatchfulSubmitter) -> ChatViewModel {
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default,
        jobSubmitter: submitter)
    vm.onAppear()
    Task {
        await vm.runJob(
            preface: "Voy a mirar.",
            handoff: Handoff(goal: "revisar el disco", context: ""),
            submitter: submitter)
    }
    return vm
}

@MainActor func testStoppingReachesTheRunner() async {
    // JobRunner.cancel() existia y no lo llamaba nadie: el freno estaba
    // construido, probado y desconectado del pedal.
    let submitter = WatchfulSubmitter()
    let vm = running(submitter)
    await pumpUntil("arranca") { vm.job != nil }
    vm.cancelJob()
    await pumpUntil("llega al runner") { submitter.cancelled }
    expect(submitter.cancelled, "parar de verdad para")
}

@MainActor func testAStoppedJobDeliversNoResult() async {
    let submitter = WatchfulSubmitter()
    let vm = running(submitter)
    await pumpUntil("arranca") { vm.job != nil }
    vm.cancelJob()
    await settle(0.2)
    expect(!vm.messages.contains { $0.text == submitter.output },
           "un encargo parado no entrega su informe despues")
}

@MainActor func testWhatWasDoneIsKeptAndSaid() async {
    // "Claude keeps the work done so far": parar no es tirar lo hecho a la
    // basura en silencio.
    let submitter = WatchfulSubmitter()
    let vm = running(submitter)
    await pumpUntil("hay un paso") { !(vm.job?.steps.isEmpty ?? true) }
    vm.cancelJob()
    await settle(0.1)
    let record = vm.messages.filter(\.isStatus).map(\.text).joined(separator: " ")
    expect(record.contains("revisar el disco"),
           "queda constancia de QUE se paro: \(record)")
    // Sin cablear el idioma: se compara contra lo que el propio resumen
    // produce, que es lo que veria el usuario en su catalogo.
    guard let steps = vm.messages.first(where: { $0.isStatus })?.text else {
        expect(false, "hay registro")
        return
    }
    _ = steps
    let expected = JobSteps.summary(
        [JobStepInfo(tool: "run_shell", label: "df -h")], Localized.language())
    expect(expected != nil, "un comando nativo si deja resumen")
    if let expected {
        expect(record.contains(expected),
               "y de lo que alcanzo a hacer: \(record)")
    }
}

@MainActor func testTheCardCloses() async {
    let submitter = WatchfulSubmitter()
    let vm = running(submitter)
    await pumpUntil("arranca") { vm.job != nil }
    vm.cancelJob()
    expect(vm.job == nil,
           "una tarjeta que sigue latiendo bajo un encargo muerto miente")
}

@MainActor func testStoppingWithNoJobIsHarmless() async {
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default)
    vm.onAppear()
    let before = vm.messages.count
    vm.cancelJob()
    expectEq(vm.messages.count, before, "sin encargo, parar no escribe nada")
}

@Test @MainActor func voiceBrakeTests() {
    testTheVoiceIsOfferedTheBrake()
    testTheBrakeAsksForNothing()
    testANewTaskIsNotAStopRequest()
    testItIsToldNotToInventTheRequest()
}

@MainActor func testTheVoiceIsOfferedTheBrake() {
    // Alguien hablándole a su Mac no la está mirando: el freno tiene que
    // poder decirse, no solo pulsarse.
    for language in [AppLanguage.en, .es] {
        expectEq(ToolSpec.stopJob(language).name, "stop_job",
                 "\(language): la voz tiene una tool para parar")
    }
}

@MainActor func testTheBrakeAsksForNothing() {
    // Parar no admite matices: un argumento que el modelo pueda rellenar mal
    // es una forma de no parar.
    expect(ToolSpec.stopJob(.es).properties.isEmpty, "sin parámetros")
    expect(ToolSpec.stopJob(.es).required.isEmpty, "y sin nada obligatorio")
}

@MainActor func testANewTaskIsNotAStopRequest() {
    // El bug real: "tambien busca cines" durante una busqueda de parques hizo
    // que el modelo llamara a stop_job y matara las dos.
    for language in [AppLanguage.en, .es] {
        let text = ToolSpec.stopJob(language).description.lowercased()
        expect(text.contains("queued") || text.contains("encola"),
               "\(language): se le dice que lo otro se encola, no que pare")
    }
}

@MainActor func testItIsToldNotToInventTheRequest() {
    // Misma disciplina que resolve_approval: no se inventa una intención que
    // la usuaria no expresó.
    // Se afirma la propiedad, no la palabra: el disparador tiene que estar
    // acotado a una peticion EXPLICITA, se redacte como se redacte.
    for language in [AppLanguage.en, .es] {
        let text = ToolSpec.stopJob(language).description.lowercased()
        expect(text.contains("only") || text.contains("solo"),
               "\(language): el disparador esta acotado")
        expect(text.contains("explicit") || text.contains("explícita"),
               "\(language): y exige que lo pida de forma explicita")
    }
}
