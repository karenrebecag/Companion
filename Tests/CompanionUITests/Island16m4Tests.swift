import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Wave 16m-4: the dictation result card and the system notices. The card
// needs the pasted words to live in the projection for as long as the card
// does (and not a moment longer); the notices need to know which measured
// grid each failure sits on. Both are decided in pure code, pinned here
// before any view.

// MARK: - Dictation: what the machine keeps

@Test func dictationCardMachineTests() {
    testDictatedKeepsTheWordsForTheCard()
    testADictationWithoutWordsKeepsTheShortBeat()
    testHidingTheCardLeavesTheIsland()
    testHidingOnlyActsOnTheCard()
    testTheWordsLeaveWithTheCard()
}

private func dictated(_ text: DictatedText? = "hola qué tal") -> (SessionMachine, [SessionEffect]) {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.dictating(app: "Slack"))
    _ = machine.handle(.released)
    let effects = machine.handle(.dictated(app: "Slack", text: text))
    return (machine, effects)
}

func testDictatedKeepsTheWordsForTheCard() {
    let (machine, effects) = dictated()
    expectEq(machine.projection.dictatedText, "hola qué tal", "16m-4: la tarjeta lee lo pegado")
    expectEq(machine.projection.dictation, "Slack", "16m-4: y dice dónde")
    expect(effects.contains(.scheduleCompletedExpiry(SessionMachine.dictationCardDelay, floor: nil)),
           "16m-4: la tarjeta espera lo suyo, no el latido de 1,5 s")
    expect(SessionMachine.dictationCardDelay > SessionMachine.settleDelay,
           "16m-4: da tiempo de copiar")
}

func testADictationWithoutWordsKeepsTheShortBeat() {
    for empty in [nil, ""] as [DictatedText?] {
        let (machine, effects) = dictated(empty)
        expect(effects.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
               "16m-4: sin texto no hay tarjeta que esperar (\(empty.map { $0.value } ?? "nil"))")
        expectEq(IslandState.from(machine.projection, pebbleHidden: false).line, .dictated("Slack"),
                 "16m-4: sin texto queda la línea «pegado en» (\(empty.map { $0.value } ?? "nil"))")
    }
}

func testHidingTheCardLeavesTheIsland() {
    var (machine, _) = dictated()
    _ = machine.handle(.dictationHidden)
    expectEq(machine.projection.kind, .idle, "16m-4: ocultar devuelve la isla al reposo")
    expectEq(machine.projection.dictatedText, nil, "16m-4: ocultar suelta el texto")
    expectEq(machine.projection.dictation, nil, "16m-4: y el nombre de la app")
}

func testHidingOnlyActsOnTheCard() {
    var listening = SessionMachine()
    _ = listening.handle(.pressed)
    let effects = listening.handle(.dictationHidden)
    expectEq(listening.projection.kind, .listening, "16m-4: ocultar no corta un hold")
    expectEq(effects, [], "16m-4: ni produce efectos")
}

func testTheWordsLeaveWithTheCard() {
    var (expired, _) = dictated()
    _ = expired.handle(.completedTimerExpired)
    expectEq(expired.projection.dictatedText, nil, "16m-4: al expirar la tarjeta el texto se va")

    var (next, _) = dictated()
    _ = next.handle(.pressed)
    expectEq(next.projection.dictatedText, nil, "16m-4: un hold nuevo no hereda el texto")

    var (stopped, _) = dictated()
    _ = stopped.handle(.stop)
    expectEq(stopped.projection.dictatedText, nil, "16m-4: parar tampoco lo deja")
}

// MARK: - Dictation: what the island paints

@Test func dictationCardProjectionTests() {
    let (machine, _) = dictated()
    let state = IslandState.from(machine.projection, pebbleHidden: false)
    expectEq(state.size, .card, "16m-4: el resultado es una tarjeta, no la barra")
    expectEq(state.line, .dictationResult(app: "Slack", text: DictatedText("hola qué tal")),
             "16m-4: la línea lleva app y texto")
    expectEq(state.light, .none, "16m-4: dictar no enciende la luz verde")
}

@MainActor @Test func dictationMetricsMatchIncredible() {
    expectEq(IslandDictationMetrics.gap, 10, "16m-4 dictado: gap 10")
    expectEq([IslandDictationMetrics.textSize, IslandDictationMetrics.textLeading,
              IslandDictationMetrics.textTracking], [15, 1.38, -0.01],
             "16m-4 dictado: 15 con 1.38 y -0.01em")
}

@MainActor @Test func dictationCopyGoesToThePasteboard() {
    let board = NSPasteboard(name: NSPasteboard.Name("companion.test.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    IslandDictation.copy("línea uno\nlínea dos 🎙", to: board)
    expectEq(board.string(forType: .string), "línea uno\nlínea dos 🎙",
             "16m-4: copiar deja el texto entero, saltos y emoji incluidos")
    IslandDictation.copy("segundo", to: board)
    expectEq(board.string(forType: .string), "segundo", "16m-4: copiar reemplaza, no acumula")
}

// MARK: - Notices: which grid each failure sits on

@Test @MainActor func noticeGridTests() async {
    await Localized.scoped(to: .es) {
        expectEq(IslandNotice.content(for: .failure(.quotaExceeded))?.grid, .limit,
                 "16m-4: sin crédito es el aviso de límite")
        expectEq(IslandNotice.content(for: .failure(.quotaExceeded))?.action, .openKeys,
                 "16m-4: y su salida abre Claves")
        for failure in [TurnFailure.micDenied, .speechDenied, .accessibilityDenied] {
            expectEq(IslandNotice.content(for: .permission(failure))?.grid, .permission,
                     "16m-4: \(failure) es un permiso")
        }
        for failure in [TurnFailure.sessionDropped, .networkUnavailable, .micUnavailable, .speechEngine,
                        .noProviders] {
            expectEq(IslandNotice.content(for: .failure(failure))?.grid, .diagnostic,
                     "16m-4: \(failure) es diagnóstico")
        }
        expectEq(IslandNotice.content(for: .chatError("No se pudo guardar"))?.grid, .diagnostic,
                 "16m-4: el error del chat es diagnóstico")
        expectEq(IslandNotice.content(for: .couldntHear)?.grid, .diagnostic,
                 "16m-4: «no te oí» es diagnóstico")
        expectEq(IslandNotice.content(for: .updateAvailable(tag: "v0.9.0"))?.grid, .update,
                 "16m-4: la actualización tiene su rejilla")
    }
}

@Test @MainActor func updateNoticeContentTests() async {
    await Localized.scoped(to: .es) {
        let card = IslandNotice.content(for: .updateAvailable(tag: "v0.9.0"))
        expect(card?.title.contains("v0.9.0") == true, "16m-4 actualización: el título nombra la versión")
        expectEq(card?.action, .openUpdate, "16m-4 actualización: la acción abre la página")
        expectEq(card?.actionTitle, Localized.string("island.notice.update.action"),
                 "16m-4 actualización: el botón dice Actualizar")
        expectEq(card?.lifetime, nil,
                 "16m-4 actualización: es una oferta, espera a Después o Actualizar")
        expectEq(card?.dismissTitle, Localized.string("island.notice.update.later"),
                 "16m-4 actualización: trae su Después")
        expectEq(IslandNotice.content(for: .failure(.quotaExceeded))?.dismissTitle, nil,
                 "16m-4: solo la oferta lleva Después; el resto se cierra con el anillo o la acción")
        expectEq(IslandCopy.action(.openUpdate), Localized.string("island.notice.update.action"),
                 "16m-4 actualización: el chip de la barra habla igual")
    }
}

/// Sibling bug found while reading the shared function: any notice that
/// leaves on its own answered its button with "Check microphone".
@Test @MainActor func everyActionSaysItsOwnWord() async {
    await Localized.scoped(to: .es) {
        let connect = IslandNotice.content(for: .connectApp(slug: "notion", name: "Notion"))
        expectEq(connect?.actionTitle, Localized.string("island.connectApp.action"),
                 "16m-4: conectar una app no dice «Revisar micrófono»")
        let hear = IslandNotice.content(for: .couldntHear)
        expectEq(hear?.actionTitle, Localized.string("island.notice.checkMic"),
                 "16m-4: «no te oí» sigue diciendo Revisar micrófono")
        let keys = IslandNotice.content(for: .failure(.quotaExceeded))
        expectEq(keys?.actionTitle, Localized.string("island.action.keys"),
                 "16m-4: el límite abre Claves con su palabra")
        let permission = IslandNotice.content(for: .permission(.micDenied))
        expectEq(permission?.actionTitle, Localized.string("permission.open"),
                 "16m-4: el permiso abre Ajustes del sistema")
        expectEq(IslandNotice.content(for: .failure(.sessionDropped))?.actionTitle, nil,
                 "16m-4: sin salida real no hay botón")
    }
}

// MARK: - Update: what the island offers, and when

@Test func updateNoticeProjectionTests() {
    let idle = SessionProjection()
    let offered = IslandState.from(idle, pebbleHidden: false, update: "v0.9.0")
    expectEq(offered.size, .wideCard, "16m-6: la actualización es una tarjeta ancha (16m-4 la dejaba en 492)")
    expectEq(offered.line, .updateAvailable(tag: "v0.9.0"), "16m-4: nombra la versión")
    expectEq(offered.action, .openUpdate, "16m-4: y trae su salida")
    expectEq(IslandState.from(idle, pebbleHidden: false).line, .none,
             "16m-4: sin actualización, la isla descansa")

    var listening = SessionProjection()
    listening.kind = .listening
    expect(IslandState.from(listening, pebbleHidden: false, update: "v0.9.0").line != .updateAvailable(tag: "v0.9.0"),
           "16m-4: nunca tapa un hold")

    var noticed = SessionProjection()
    noticed.notice = .couldntHear
    expectEq(IslandState.from(noticed, pebbleHidden: false, update: "v0.9.0").line, .couldntHear,
             "16m-4: un aviso de sesión pasa por delante")

    expect(IslandState.from(idle, pebbleHidden: false, errorText: "x", update: "v0.9.0").line
        != .updateAvailable(tag: "v0.9.0"), "16m-4: un error del chat pasa por delante")

    var hovering = SessionProjection()
    hovering.kind = .hover
    expect(IslandState.from(hovering, pebbleHidden: false, update: "v0.9.0").line
        != .updateAvailable(tag: "v0.9.0"), "16m-4: con el puntero encima manda el campo")
}

@MainActor @Test func updateDismissalTests() {
    let available = UpdateState.Available(tag: "v0.9.0", pageURL: URL(fileURLWithPath: "/tmp/x"))
    expectEq(IslandUpdate.visibleTag(available: available, dismissed: nil), "v0.9.0",
             "16m-4: hay versión y nadie la despidió")
    expectEq(IslandUpdate.visibleTag(available: available, dismissed: "v0.9.0"), nil,
             "16m-4: despedida, no vuelve en esta sesión")
    expectEq(IslandUpdate.visibleTag(available: available, dismissed: "v0.8.0"), "v0.9.0",
             "16m-4: despedir una versión no calla la siguiente")
    expectEq(IslandUpdate.visibleTag(available: nil, dismissed: nil), nil, "16m-4: sin versión no hay nada")

    let state = UpdateState(checkNow: { nil })
    state.found(available)
    expectEq(state.noticeTag, "v0.9.0", "16m-4: el estado ofrece la versión hallada")
    state.dismissNotice()
    expectEq(state.noticeTag, nil, "16m-4: despedirla la retira")
    state.found(.init(tag: "v1.0.0", pageURL: available.pageURL))
    expectEq(state.noticeTag, "v1.0.0", "16m-4: una versión más nueva vuelve a ofrecerse")
}

// MARK: - Notices: on the island's grid

// Arc: status tones mean status, and the island's grid gives every notice the
// same column rule instead of a measured width per kind.
@MainActor @Test func noticeToneFollowsWhatItMeans() {
    expectEq(IslandNotice.tone(.diagnostic).hex, ArcTone.danger.hex, "un fallo es danger")
    expectEq(IslandNotice.tone(.limit).hex, ArcTone.warning.hex, "un limite pide atencion")
    expectEq(IslandNotice.tone(.permission).hex, ArcTone.warning.hex, "un permiso pide atencion")
    expectEq(IslandNotice.tone(.update).hex, ArcTone.accent.hex, "una oferta es informacion")
}

@MainActor @Test func aNoticeFillsTheIslandColumn() throws {
    let content = try #require(IslandNotice.content(for: .couldntHear))
    let card = IslandNoticeCard(content: content, pausesClock: false, onHover: { _ in }, onAction: { _ in },
                                onDismiss: {})
        .frame(width: IslandGrid.openColumn)
    let image = try #require(ImageRenderer(content: card.environment(\.colorScheme, .dark)).nsImage)
    expectEq(image.size.width, IslandGrid.openColumn, "el aviso llena la columna de la isla")
}

// MARK: - Catalog

@Test func islandNoticeCatalogKeysExist() {
    let keys = ["island.dictation.copy", "island.dictation.copied", "island.dictation.hide",
                "island.notice.limit.title", "island.notice.update.title", "island.notice.update.body",
                "island.notice.update.action", "island.notice.update.later"]
    for language in ["en", "es"] {
        let values = catalogKeys16m4(language)
        for key in keys {
            expect(values.contains(key), "16m-4: \(language) trae \(key)")
        }
    }
}

private func catalogKeys16m4(_ language: String) -> Set<String> {
    guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
          let file = try? String(contentsOfFile: path + "/Localizable.strings", encoding: .utf8)
    else { return [] }
    var keys: Set<String> = []
    for line in file.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\"") else { continue }
        let parts = trimmed.dropFirst().split(separator: "\"", maxSplits: 1, omittingEmptySubsequences: false)
        if let key = parts.first { keys.insert(String(key)) }
    }
    return keys
}
