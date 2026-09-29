import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 16m-6: the notices that were still missing. "Iniciar sesión" has a
// real source (a connected account whose state is `reconnect`); "consent"
// already has two (connecting an app, a refused system permission) and both
// sit on the consent grid since 16m-4. The update card also gets the room
// its measured 522 needs.

// MARK: - Sign in: the reducer and the card

@Test func signInNoticeTests() {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    let kind = machine.projection.kind
    let effects = machine.handle(.signInAppSuggested(slug: "gmail", name: "Gmail"))
    expectEq(machine.projection.notice, SessionCard.signInApp(slug: "gmail", name: "Gmail"),
             "16m-6 sesión: el evento levanta la tarjeta")
    expectEq(machine.projection.kind, kind, "16m-6 sesión: es un aviso, no una transición del turno")
    expect(effects.contains(.scheduleNoticeExpiry(SessionMachine.noticeDelay)),
           "16m-6 sesión: se va sola, como el aviso de conectar")
    _ = machine.handle(.noticeExpired)
    expect(machine.projection.notice == nil, "16m-6 sesión: expira")

    var projection = SessionProjection()
    projection.notice = .signInApp(slug: "gmail", name: "Gmail")
    let card = IslandState.from(projection, pebbleHidden: false)
    expectEq(card.size, IslandState.Size.card, "16m-6 sesión: tarjeta")
    expectEq(card.line, IslandState.Line.signInApp(slug: "gmail", name: "Gmail"), "16m-6 sesión: nombra la app")
    expectEq(card.action, IslandState.Action.openApps(slug: "gmail"), "16m-6 sesión: la salida abre la página Apps")
}

@Test @MainActor func signInNoticeContentTests() async {
    await pinLanguage(.en) {
        let content = IslandNotice.content(for: .signInApp(slug: "gmail", name: "Gmail"))
        expectEq(content?.grid, .limit, "16m-6 sesión: la rejilla de límite (investigación §5)")
        expectEq(content?.action, .openApps(slug: "gmail"), "16m-6 sesión: abre Apps en esa app")
        expectEq(content?.lifetime, SessionMachine.noticeDelay, "16m-6 sesión: una oferta sin respuesta no se queda")
        expectEq(content?.actionTitle, Localized.string("island.signIn.action"), "16m-6 sesión: su propio verbo")
        expect(content?.title.contains("Gmail") == true, "16m-6 sesión: dice de qué app")
        let connect = IslandNotice.content(for: .connectApp(slug: "gmail", name: "Gmail"))
        expect(content?.title != connect?.title, "16m-6 sesión: no se confunde con «conectar»")
        expect(content?.actionTitle != connect?.actionTitle, "16m-6 sesión: ni en el botón")
        expect(content?.body?.isEmpty == false, "16m-6 sesión: explica por qué")
    }
    await pinLanguage(.es) {
        let content = IslandNotice.content(for: .signInApp(slug: "gmail", name: "Gmail"))
        expect(content?.title.contains("Gmail") == true && content?.title.contains("sesión") == true,
               "16m-6 sesión es: el texto va en español")
    }
    expectEq(IslandNotice.announcement(IslandNotice.content(for: .signInApp(slug: "s", name: "Slack"))!).isEmpty, false,
             "16m-6 sesión: VoiceOver lo anuncia al aparecer")
}

// MARK: - Sign in: the source

private final class ReconnectAppsService: AppsService, @unchecked Sendable {
    func catalog(query: String, after: String?) async throws -> CatalogPage { CatalogPage(apps: [], total: 0, next: nil) }
    func accounts() async throws -> [ConnectedAccount] {
        [ConnectedAccount(id: "apn_1", app: "slack_v2", name: nil, state: .connected),
         ConnectedAccount(id: "apn_2", app: "gmail", name: nil, state: .reconnect)]
    }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] { [] }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        AppCallResult(isError: false, text: "")
    }
}

private final class Nudges: @unchecked Sendable {
    let lock = NSLock()
    var signIn: [String] = []
    var connect: [String] = []
}

@Test func runnerSignInSourceTests() async {
    let nudges = Nudges()
    let runner = AppToolRunner(
        service: { ReconnectAppsService() },
        catalog: [AppMention.Candidate(slug: "gmail", name: "Gmail")],
        suggest: { slug, _ in nudges.lock.withLock { nudges.connect.append(slug) } },
        signIn: { slug, name in nudges.lock.withLock { nudges.signIn.append("\(slug):\(name)") } })

    runner.noteTurn("mira mi gmail")
    expect(nudges.signIn.isEmpty && nudges.connect.isEmpty,
           "16m-6 fuente: sin cuentas cargadas no se sabe si caducó (mismo motivo que M2)")

    await runner.refresh()
    runner.noteTurn("dime la hora")
    expect(nudges.signIn.isEmpty, "16m-6 fuente: si el turno no nombra la app, no hay aviso")
    runner.noteTurn("mira mi Gmail por favor")
    expectEq(nudges.signIn, ["gmail:Gmail"], "16m-6 fuente: nombrar una cuenta caducada ofrece iniciar sesión")
    expect(nudges.connect.isEmpty, "16m-6 fuente: y no la trata como una app sin conectar")
    runner.noteTurn("otra vez gmail")
    expectEq(nudges.signIn.count, 1, "16m-6 fuente: una sola vez por arranque")
    runner.noteTurn("manda un slack")
    expectEq(nudges.signIn.count, 1, "16m-6 fuente: una app conectada y vigente no avisa")
}

@Test func runnerWithoutSignInHandlerStillWorksTests() async {
    let runner = AppToolRunner(service: { ReconnectAppsService() }, catalog: [], suggest: nil)
    await runner.refresh()
    runner.noteTurn("mira mi gmail")
    expectEq(runner.specs(.en).count, 0, "16m-6 fuente: sin manejador no pasa nada y no hay herramientas de la caducada")
}

// MARK: - The update card's room

@Test @MainActor func updateCardRoomTests() {
    expectEq(IslandNoticeMetrics.updateWidth, 522, "16m-6 ancho: el aviso mide 522 (investigación §5)")
    expectEq(IslandChrome.wideCardWidth, IslandNoticeMetrics.updateWidth + 2 * Space.x4,
             "16m-6 ancho: la forma da los 522 del aviso más el margen de la isla")
    expectEq(IslandChrome.cardWidth, 492, "16m-6 ancho: las demás tarjetas siguen en 492")
    let room = IslandChrome.wideCardWidth - 2 * Space.x4
    expectEq(IslandNoticeMetrics.width(.update, available: room), 522, "16m-6 ancho: el aviso ya no se recorta")
    expectEq(IslandNoticeMetrics.width(.update, available: IslandChrome.cardWidth - 2 * Space.x4), 460,
             "16m-6 ancho: en la forma estrecha seguía recortado, por eso ensancha")
    expect(IslandChrome.canvasWidth >= IslandChrome.wideCardWidth + 2 * 20,
           "16m-6 ancho: el lienzo aguanta la forma con sus hombros y su sombra")

    let notch = NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 945,
        safeTop: 38, leftAuxWidth: 662, rightAuxWidth: 662))
    expectEq(IslandChrome.width(for: .wideCard, notch: notch), IslandChrome.wideCardWidth, "16m-6 ancho: el rol ancho")
    expectEq(IslandChrome.shapeSize(for: .wideCard, contentHeight: 120, notch: notch).width,
             IslandChrome.wideCardWidth, "16m-6 ancho: la forma dibujada")
    expectEq(IslandChrome.width(for: .card, notch: notch), 492, "16m-6 ancho: la tarjeta normal no cambia")

    var idle = SessionProjection()
    idle.kind = .idle
    let offer = IslandState.from(idle, pebbleHidden: false, update: "v0.9.0")
    expectEq(offer.line, .updateAvailable(tag: "v0.9.0"), "16m-6 ancho: la oferta sigue siendo la oferta")
    expectEq(offer.size, .wideCard, "16m-6 ancho: solo la oferta de actualización usa la forma ancha")
    expect(IslandState.Size.allCases.contains(.wideCard), "16m-6 ancho: el rol está en el catálogo de tamaños")
}
