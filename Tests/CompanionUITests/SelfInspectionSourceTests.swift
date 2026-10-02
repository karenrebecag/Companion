import CompanionCore
@testable import CompanionUI
import CompanionUITestSupport
import CompanionTestKit
import Foundation
import Testing

// Spec self-qa-inspeccion, PR-4: the UI side of the read port. The source
// reads what the app already holds; the mirror keeps what the UI painted, so
// what gets inspected is what was shown, not a reconstruction.

private let sentinel = "SENTINEL-7f3a-ZXQ"

@MainActor private func source(
    _ chat: ChatViewModel = chat(),
    mirror: InspectionMirror = InspectionMirror(),
    languageStored: @escaping @MainActor () -> AppLanguage? = { nil }
) -> SelfInspectionSource {
    SelfInspectionSource(session: chat.session, chat: chat, mirror: mirror, languageStored: languageStored)
}

@Test @MainActor func sourceReadsProjectionAndThreadWithoutTitle() async {
    let model = chat()
    let photo = AttachmentRef(name: "foto.jpg", path: "/nonexistent/foto.jpg", kind: .image)
    model.messages = [
        ChatMessage(role: .user, text: "hola \(sentinel)", attachments: [photo, photo]),
        ChatMessage(role: .assistant, text: "respuesta"),
        ChatMessage(isStatus: true, text: "estado", isFailure: true),
        ChatMessage(role: .user, text: "elegida", origin: .choice, restored: true),
    ]
    let read = source(model)
    expectEq(await read.session(), model.session.projection, "fuente: la proyeccion tal cual")
    let expected = [
        ThreadMessageInput(role: .user, isStatus: false, origin: .typed, isFailure: false, restored: false,
                           attachments: 2, text: "hola \(sentinel)"),
        ThreadMessageInput(role: .assistant, isStatus: false, origin: .typed, isFailure: false, restored: false,
                           attachments: 0, text: "respuesta"),
        ThreadMessageInput(role: nil, isStatus: true, origin: .typed, isFailure: true, restored: false,
                           attachments: 0, text: "estado"),
        ThreadMessageInput(role: .user, isStatus: false, origin: .choice, isFailure: false, restored: true,
                           attachments: 0, text: "elegida"),
    ]
    // Exact equality: one input per message and nothing else, so the thread
    // title (derived from the first user message) never becomes an entry.
    expectEq(await read.activeThread(), expected, "fuente: cada mensaje del hilo, sin titulo")
}

@Test @MainActor func sourceSettingsReadsLanguageStoredAndEffective() async {
    await pinLanguage(.es) {
        let following = await source(languageStored: { nil }).settings()
        expectEq(following.languageStored, nil, "ajustes: sin eleccion, sigue al sistema")
        expectEq(following.languageEffective, "es", "ajustes: el idioma con el que habla la app")
    }
    await pinLanguage(.en) {
        let chosen = await source(languageStored: { .en }).settings()
        expectEq(chosen.languageStored, "en", "ajustes: el idioma que eligio")
        expectEq(chosen.languageEffective, "en", "ajustes: y el efectivo")
    }
}

@Test @MainActor func mirrorPaintKeepsCatalogTextOnlyForTextFreeLines() async {
    await pinLanguage(.en) {
        let mirror = InspectionMirror()
        mirror.paint(IslandState(size: .nudge, line: .thinking))
        expectEq(mirror.island?.catalogText, IslandCopy.line(.thinking), "espejo: la copia del catalogo")
        expect(mirror.island?.catalogText?.isEmpty == false, "espejo: la copia no esta vacia")
        mirror.paint(IslandState(size: .card, line: .followUp(sentinel)))
        expectEq(mirror.island?.state.line, .followUp(sentinel), "espejo: guarda lo pintado")
        expectEq(mirror.island?.catalogText, nil, "espejo: una linea con contenido no deja texto")
        mirror.paint(IslandState(size: .card, line: .chatError(sentinel)))
        expectEq(mirror.island?.catalogText, nil, "espejo: tampoco un error del chat")
    }
}

@Test @MainActor func mirrorScreenMapsMainPageAndSettingsTab() {
    let mirror = InspectionMirror()
    mirror.show(page: .home, settingsOpen: false, settingsTab: .voice)
    expectEq(mirror.screen, InspectedScreen(settingsOpen: false, settingsTab: nil, page: "home"),
             "espejo: con Ajustes cerrado no hay pestana")
    mirror.show(page: .apps, settingsOpen: true, settingsTab: .privacy)
    expectEq(mirror.screen, InspectedScreen(settingsOpen: true, settingsTab: "privacy", page: "apps"),
             "espejo: pagina y pestana por su nombre estable")
    for tab in SettingsTab.allCases {
        mirror.show(page: .home, settingsOpen: true, settingsTab: tab)
        expectEq(mirror.screen?.settingsTab, tab.rawValue, "espejo: \(tab.rawValue) no se traduce")
    }
}

/// What PR-4 leaves until PR-5 wires the views: an unpainted mirror answers
/// nil, which the runner turns into `not_available`.
@Test @MainActor func emptyMirrorLeavesIslandAndScreenUnanswered() async {
    let read = source()
    expectEq(await read.island(), nil, "espejo vacio: sin isla")
    expectEq(await read.screen(), nil, "espejo vacio: sin pantalla")
}

@Test @MainActor func sourceReadsWhatTheMirrorHolds() async {
    let mirror = InspectionMirror()
    let read = source(mirror: mirror)
    mirror.paint(IslandState(size: .nudge))
    mirror.show(page: .home, settingsOpen: false, settingsTab: .general)
    expectEq(await read.island(), mirror.island, "fuente: la isla del espejo")
    expectEq(await read.screen(), mirror.screen, "fuente: la pantalla del espejo")
}
