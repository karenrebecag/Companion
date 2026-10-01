import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// Code review 2026-09-24 (medio): spec 15d §5 promised a visible notice
// while transcript debugging writes the user's words to disk. The status
// line and the island's hover both say so, from `Config.debugTranscripts`.

@Test @MainActor func transcriptDebugNoticeTests() async {
    testTheViewModelExposesTheDebugFlag()
    testTheIslandHoverSaysDebuggingIsOn()
    await testTheNoticeIsInBothCatalogs()
}

@MainActor func testTheViewModelExposesTheDebugFlag() {
    let on = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([:]),
        store: MemoryConversationStore(), config: Config(debugTranscripts: true))
    expect(on.debugTranscripts, "aviso: el modelo sabe que la depuración está activa")
    let off = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([:]),
        store: MemoryConversationStore(), config: Config(debugTranscripts: false))
    expect(!off.debugTranscripts, "aviso: apagada, no hay aviso")
}

@MainActor func testTheIslandHoverSaysDebuggingIsOn() {
    var hover = SessionProjection()
    hover.kind = .hover
    let on = IslandState.from(hover, pebbleHidden: false, holdLearned: true, debugTranscripts: true)
    expectEq(on.line, .transcriptsDebug, "aviso: el hover de la island lo dice")
    let learning = IslandState.from(hover, pebbleHidden: false, debugTranscripts: true)
    expectEq(learning.line, .transcriptsDebug, "aviso: gana a la pista del hold")
    let blocked = IslandState.from(
        hover, pebbleHidden: false, keyListening: false, debugTranscripts: true)
    expectEq(blocked.line, .keyBlocked, "aviso: una tecla muerta sigue siendo lo primero")
    let off = IslandState.from(hover, pebbleHidden: false, holdLearned: true)
    expectEq(off.line, IslandState.Line.none, "aviso: apagada, el hover no cambia")
}

@MainActor func testTheNoticeIsInBothCatalogs() async {
    await Localized.scoped(to: .es) {
        expectEq(Localized.string("debug.transcriptsOn"), "Depuración de transcripciones activa",
                 "aviso: copy en español")
        expectEq(IslandCopy.line(.transcriptsDebug), "Depuración de transcripciones activa",
                 "aviso: la island lo pinta del catálogo")
    }
    await Localized.scoped(to: .en) {
        expectEq(Localized.string("debug.transcriptsOn"), "Transcript debugging is on",
                 "aviso: copy en inglés")
    }
}
