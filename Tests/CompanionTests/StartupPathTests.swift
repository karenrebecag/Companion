import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

@Test @MainActor func startupPathTests() async {
    await testKeyPresentSkipsTheProbe()
    await testProbeResolvesToBaseWhenSomethingIsAlive()
    await testALivePathStillAsksForOneConfirmation()
    await testNothingAliveEndsInNone()
    await testTheLocalPathNeverGoesOutToOpenAI()
    await testAcceptLocalBaseUnlocksAndPersists()
    await testSavedPathIsAutoAcceptedOnRelaunch()
    await testSavedPathThatDiedIsNotAutoAccepted()
    await testSendReachesTheProviderAfterAccepting()
    await testChangeKeyDoesNotJailAnAcceptedLocalUser()
    await testChangeKeyStillJailsWhenThereIsNoLocalBase()
    await testChatIsNeverShownWhileProbing()
}

final class FakeStartupProbe: StartupProbing, @unchecked Sendable {
    private let paths: [LocalPath]
    private let lock = NSLock()
    private var _calls: [String?] = []

    init(_ paths: [LocalPath]) { self.paths = paths }

    var calls: [String?] {
        lock.lock(); defer { lock.unlock() }; return _calls
    }

    func probe(preferred: String?) async -> [LocalPath] {
        record(preferred)
        return paths
    }

    private func record(_ preferred: String?) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(preferred)
    }
}

@MainActor private func local(
    _ probe: FakeStartupProbe,
    chat: FakeChatProvider = FakeChatProvider(),
    secrets: TestSecretStore = TestSecretStore(),
    store: MemoryConversationStore = MemoryConversationStore()
) -> ChatViewModel {
    ProviderPreference.forget()
    return ChatViewModel(
        chat: chat, secrets: secrets, store: store, config: .default,
        startupProbe: probe)
}

@MainActor func testKeyPresentSkipsTheProbe() async {
    // Un arranque con clave no puede pagar el precio de sondear un daemon que
    // no le importa: el camino premium sigue siendo tan rapido como era.
    let probe = FakeStartupProbe([.ollama(model: "qwen3:14b")])
    let vm = local(probe, secrets: TestSecretStore([.openAI: "sk-test"]))
    vm.onAppear()
    await settle()
    expectEq(vm.startup, .premium, "con clave el arranque es premium")
    expect(!vm.needsOnboarding, "y entra directo")
    expectEq(probe.calls.count, 0, "el sondeo ni se lanza")
}

@MainActor func testProbeResolvesToBaseWhenSomethingIsAlive() async {
    let probe = FakeStartupProbe([.ollama(model: "qwen3:14b")])
    let vm = local(probe)
    vm.onAppear()
    await settle()
    expectEq(vm.startup, .base([.ollama(model: "qwen3:14b")]),
             "el sondeo reporta el camino vivo")
}

@MainActor func testALivePathStillAsksForOneConfirmation() async {
    // Decision de la tabla de estados: encontrar un camino no es aceptarlo.
    // El usuario ve UNA pantalla que dice con que va a hablar, y sigue.
    let probe = FakeStartupProbe([.ollama(model: "qwen3:14b")])
    let vm = local(probe)
    vm.onAppear()
    await settle()
    expect(vm.needsOnboarding, "un camino vivo se presenta, no se asume")
}

@MainActor func testNothingAliveEndsInNone() async {
    let vm = local(FakeStartupProbe([]))
    vm.onAppear()
    await settle()
    expectEq(vm.startup, .none, "sin caminos, el estado lo dice")
    expect(vm.needsOnboarding, "y sigue pidiendo algo")
}

@MainActor func testTheLocalPathNeverGoesOutToOpenAI() async {
    // Wave 9 ya cerro esta forma de bug en el guardia de clave: no se sale a
    // la red a confirmar algo que no existe.
    let chat = FakeChatProvider()
    let vm = local(FakeStartupProbe([.ollama(model: "qwen3:14b")]), chat: chat)
    vm.onAppear()
    await settle()
    vm.acceptLocalBase(.ollama(model: "qwen3:14b"))
    expectEq(chat.verifyProviders.count, 0, "el camino local no verifica claves")
    expectEq(chat.verifyKeys.count, 0, "ni manda una sola")
}

@MainActor func testAcceptLocalBaseUnlocksAndPersists() async {
    let vm = local(FakeStartupProbe([.ollama(model: "qwen3:14b")]))
    vm.onAppear()
    await settle()
    vm.acceptLocalBase(.ollama(model: "qwen3:14b"))
    expect(!vm.needsOnboarding, "aceptar abre la app")
    expectEq(ProviderPreference.name, "Ollama", "y guarda el proveedor")
    expectEq(ProviderPreference.localModel, "qwen3:14b", "y el tag elegido")
    ProviderPreference.forget()
}

@MainActor func testSavedPathIsAutoAcceptedOnRelaunch() async {
    let probe = FakeStartupProbe([.ollama(model: "qwen3:14b")])
    let first = local(probe)
    first.onAppear()
    await settle()
    first.acceptLocalBase(.ollama(model: "qwen3:14b"))

    // Segundo arranque: mismo camino vivo, cero clics.
    let second = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore(),
        store: MemoryConversationStore(), config: .default,
        startupProbe: probe)
    second.onAppear()
    await settle()
    expect(!second.needsOnboarding, "lo aceptado sobrevive al relaunch")
    expectEq(probe.calls.last, "qwen3:14b",
             "y el sondeo pregunta por el tag guardado")
    ProviderPreference.forget()
}

@MainActor func testSavedPathThatDiedIsNotAutoAccepted() async {
    let probe = FakeStartupProbe([.ollama(model: "qwen3:14b")])
    let first = local(probe)
    first.onAppear()
    await settle()
    first.acceptLocalBase(.ollama(model: "qwen3:14b"))

    // El usuario borro ese modelo entre arranques.
    let second = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore(),
        store: MemoryConversationStore(), config: .default,
        startupProbe: FakeStartupProbe([.ollama(model: "otro:8b")]))
    second.onAppear()
    await settle()
    expect(second.needsOnboarding,
           "un camino guardado que ya no existe no se da por bueno")
    ProviderPreference.forget()
}

@MainActor func testSendReachesTheProviderAfterAccepting() async {
    // El guardia de send() era medio muro: sin esto, aceptar no sirve de nada.
    let chat = FakeChatProvider()
    let vm = local(FakeStartupProbe([.ollama(model: "qwen3:14b")]), chat: chat)
    vm.onAppear()
    await settle()
    vm.acceptLocalBase(.ollama(model: "qwen3:14b"))
    vm.draft = "hola"
    vm.send()
    await settle()
    expectEq(chat.histories.count, 1, "sin ninguna clave, el mensaje sale")
    ProviderPreference.forget()
}

@MainActor func testChangeKeyDoesNotJailAnAcceptedLocalUser() async {
    let vm = local(FakeStartupProbe([.ollama(model: "qwen3:14b")]))
    vm.onAppear()
    await settle()
    vm.acceptLocalBase(.ollama(model: "qwen3:14b"))
    vm.changeKey()
    expect(!vm.needsOnboarding,
           "tocar la clave no puede dejar mudo a quien ya hablaba en local")
    ProviderPreference.forget()
}

@MainActor func testChangeKeyStillJailsWhenThereIsNoLocalBase() async {
    let vm = local(FakeStartupProbe([]), secrets: TestSecretStore([.openAI: "sk-test"]))
    vm.onAppear()
    await settle()
    vm.changeKey()
    expect(vm.needsOnboarding, "sin camino local, quitar la clave si cierra la puerta")
}

@MainActor func testChatIsNeverShownWhileProbing() async {
    // El parpadeo que la spec prohibe: la raiz no puede pintar el hilo y
    // volver al onboarding. Mientras se sondea, needsOnboarding no se suelta.
    let vm = local(FakeStartupProbe([.ollama(model: "qwen3:14b")]))
    vm.onAppear()
    expectEq(vm.startup, .probing, "arranca sondeando")
    expect(vm.needsOnboarding, "y no suelta la puerta mientras tanto")
    await settle()
}

@Test @MainActor func providerOrderTests() async {
    testANewProviderLandsAtTheEndNotTheFront()
    testUnknownIdsAreIgnoredNotFatal()
    await testAcceptingALocalPathPutsItFirst()
    await testAcceptingTwiceDoesNotDuplicate()
}

@MainActor func testANewProviderLandsAtTheEndNotTheFront() {
    // Instalar Ollama no puede reordenar lo que el usuario ya decidio, y un
    // proveedor que nunca vio no puede nacer apagado: no hay como encenderlo.
    let order = ["openrouter", "openai"]
    let names = ProviderDescriptor.route(order: order).map(\.name)
    expectEq(names, ["OpenRouter", "OpenAI", "Ollama"],
             "lo nombrado manda; lo nuevo va detras, no fuera")
}

@MainActor func testUnknownIdsAreIgnoredNotFatal() {
    // Una preferencia de una version futura, o un proveedor retirado.
    let names = ProviderDescriptor.route(order: ["gemini", "ollama"]).map(\.name)
    expectEq(names.first, "Ollama", "el id valido manda")
    expectEq(names.count, ProviderDescriptor.catalog.count,
             "y el desconocido no borra ni duplica filas")
}

@MainActor func testAcceptingALocalPathPutsItFirst() async {
    // Quien elige hablar con su propio Mac lo quiere primero, no de respaldo.
    ProviderPreference.forget()
    let vm = local(FakeStartupProbe([.ollama(model: "qwen3:14b")]))
    vm.onAppear()
    await settle()
    vm.acceptLocalBase(.ollama(model: "qwen3:14b"))
    expectEq(ProviderPreference.order.first, "ollama",
             "aceptar la base local es tambien una opinion sobre la escalera")
    ProviderPreference.forget()
}

@MainActor func testAcceptingTwiceDoesNotDuplicate() async {
    ProviderPreference.forget()
    let vm = local(FakeStartupProbe([.ollama(model: "qwen3:14b")]))
    vm.onAppear()
    await settle()
    vm.acceptLocalBase(.ollama(model: "qwen3:14b"))
    vm.acceptLocalBase(.ollama(model: "qwen3:14b"))
    expectEq(ProviderPreference.order.filter { $0 == "ollama" }.count, 1,
             "aceptar dos veces no apila la misma fila")
    ProviderPreference.forget()
}
