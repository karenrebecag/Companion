import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// 16p-1: ChatViewModel.errorText (persistence, generic chat) used to be read
// only by the old thread view, which nobody instantiated (retired in 16p-2). It must reach the island as
// a card with a way out and Home as a banner. Turn failures are the other
// family (a status line in the thread) and must not be drawn twice.

@Test @MainActor func chatErrorVisibleTests() {
    testANonNilErrorMakesTheIslandShowACard()
    testNoErrorLeavesTheIslandAtRest()
    testSessionNoticesOutrankTheChatError()
    testTheChatErrorCardCarriesTheSentenceAndAnExit()
    testTheSurfaceHidesWhatOnboardingAlreadyShows()
    testDismissClearsTheError()
    testAnErrorThatArrivesWhileComposingKeepsItsSixSeconds()
    testASupersededErrorIsNotRepaintedWhenTheNoticeLeaves()
    testIslandDismissalLivesInTheModel()
    testTheCardIsAnnounced()
}

@MainActor func testANonNilErrorMakesTheIslandShowACard() {
    let state = IslandState.from(
        SessionProjection(), pebbleHidden: false, errorText: "No se pudo guardar")
    expectEq(state.size, .card, "error de chat: la isla abre una tarjeta")
    expectEq(state.line, .chatError("No se pudo guardar"),
             "error de chat: la línea lleva la frase")
}

@MainActor func testNoErrorLeavesTheIslandAtRest() {
    let state = IslandState.from(SessionProjection(), pebbleHidden: false, errorText: nil)
    expectEq(state.line, .none, "sin error: la isla no dice nada")
    let empty = IslandState.from(SessionProjection(), pebbleHidden: false, errorText: "")
    expectEq(empty.line, .none, "error vacío: no abre una tarjeta en blanco")
}

@MainActor func testSessionNoticesOutrankTheChatError() {
    var projection = SessionProjection()
    projection.notice = .couldntHear
    let state = IslandState.from(projection, pebbleHidden: false, errorText: "x")
    expectEq(state.line, .couldntHear,
             "error de chat: un aviso de la sesión manda sobre él")
}

@MainActor func testTheChatErrorCardCarriesTheSentenceAndAnExit() {
    let content = IslandNotice.content(for: .chatError("No se pudo guardar"))
    expectEq(content?.title, "No se pudo guardar", "tarjeta de error: la frase es el título")
    expect(content?.action == nil, "tarjeta de error: sin botón inventado")
    expectEq(content?.lifetime, SessionMachine.noticeDelay,
             "tarjeta de error: sale sola como los demás avisos y trae su ×")
}

@MainActor func testTheSurfaceHidesWhatOnboardingAlreadyShows() {
    expectEq(ChatErrorSurface.visible(errorText: "x", needsOnboarding: false, dismissed: nil), "x",
             "superficie: el error se ve")
    expectEq(ChatErrorSurface.visible(errorText: "x", needsOnboarding: true, dismissed: nil), nil,
             "superficie: la bienvenida ya pinta el suyo")
    expectEq(ChatErrorSurface.visible(errorText: "x", needsOnboarding: false, dismissed: "x"), nil,
             "superficie: lo descartado no vuelve")
    expectEq(ChatErrorSurface.visible(errorText: "y", needsOnboarding: false, dismissed: "x"), "y",
             "superficie: un error distinto sí se ve")
    expectEq(ChatErrorSurface.visible(errorText: nil, needsOnboarding: false, dismissed: nil), nil,
             "superficie: sin error no hay nada")
}

@MainActor func testDismissClearsTheError() {
    let vm = makeVM()
    vm.errorText = "boom"
    vm.dismissError()
    expect(vm.errorText == nil, "descartar: el error del chat se limpia")
}

@MainActor private func makeVM() -> ChatViewModel {
    ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default)
}

/// The 6 s clock belongs to the card being on screen, not to the error
/// arriving: while the field is open the card is not drawn and nothing runs.
@MainActor func testAnErrorThatArrivesWhileComposingKeepsItsSixSeconds() {
    let vm = makeVM()
    vm.errorText = "No se pudo guardar"
    let text = ChatErrorSurface.visible(
        errorText: vm.errorText, needsOnboarding: false, dismissed: vm.dismissedIslandError)
    let composing = IslandState.from(
        SessionProjection(), pebbleHidden: false, composing: true, errorText: text)
    expect(IslandNotice.expiringChatError(composing.line) == nil,
           "M1: componiendo no se pinta la tarjeta, así que no corre el reloj")
    expect(vm.dismissedIslandError == nil, "M1: nada se marcó descartado sin verse")
    let freed = IslandState.from(
        SessionProjection(), pebbleHidden: false, composing: false, errorText: text)
    expectEq(IslandNotice.expiringChatError(freed.line), "No se pudo guardar",
             "M1: al liberarse el campo la tarjeta se ve y el reloj arranca ahí")
}

@MainActor func testASupersededErrorIsNotRepaintedWhenTheNoticeLeaves() {
    // Re-review 16p-1: only a notice that reports a failure says the same
    // thing as the chat error. A hint or a "didn't hear you" says something
    // else, and the error must still be seen once it leaves.
    for benign in [SessionCard.holdHint, .couldntHear] {
        let waiting = makeVM()
        waiting.errorText = "persistencia"
        waiting.supersedeIslandError(notice: benign)
        waiting.supersedeIslandError(notice: nil)
        expectEq(ChatErrorSurface.visible(
            errorText: waiting.errorText, needsOnboarding: false,
            dismissed: waiting.dismissedIslandError), "persistencia",
                 "M2: un aviso que no es un fallo no se traga el error de chat (\(benign))")
    }
    let vm = makeVM()
    vm.errorText = "x"
    vm.supersedeIslandError(notice: .failure(.noProviders))
    vm.supersedeIslandError(notice: nil)
    expectEq(ChatErrorSurface.visible(
        errorText: vm.errorText, needsOnboarding: false, dismissed: vm.dismissedIslandError), nil,
             "M2: el aviso de sesión ya dijo el fallo; no reaparece como error de chat")
    let calm = makeVM()
    calm.errorText = "x"
    calm.supersedeIslandError(notice: nil)
    expectEq(ChatErrorSurface.visible(
        errorText: calm.errorText, needsOnboarding: false, dismissed: calm.dismissedIslandError), "x",
             "M2: sin aviso de por medio el error se ve")
    vm.errorText = nil
    expect(vm.dismissedIslandError == nil, "M2: un error limpio rearma la isla")
    vm.errorText = "x"
    expectEq(ChatErrorSurface.visible(
        errorText: vm.errorText, needsOnboarding: false, dismissed: vm.dismissedIslandError), "x",
             "M2: el mismo texto en un error nuevo vuelve a verse")
}

/// A recreated view must not resurrect what the user waved away.
@MainActor func testIslandDismissalLivesInTheModel() {
    let vm = makeVM()
    vm.errorText = "boom"
    vm.dismissIslandError()
    expectEq(vm.dismissedIslandError, "boom", "L3: el descarte de la isla vive en el modelo")
    expectEq(vm.errorText, "boom", "L3: Home conserva su copia")
}

@MainActor func testTheCardIsAnnounced() {
    let content = IslandNotice.content(for: .chatError("No se pudo guardar"))
    expectEq(content.map(IslandNotice.announcement), "No se pudo guardar",
             "L3: VoiceOver oye la frase al aparecer")
    expectEq(ChatErrorSurface.announcement("hola"), "hola", "L3: el banner de Home también")
}
