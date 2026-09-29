import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Wave 16m-6, review round: the sign-in notice's source and reducer edges,
// and the wide card's reach.

// MARK: - Source

private final class ScriptedApps: AppsService, @unchecked Sendable {
    let lock = NSLock()
    var list: [ConnectedAccount]
    var failingTools: Set<String> = []
    var actions: [String: [AppAction]] = [:]
    init(_ list: [ConnectedAccount]) { self.list = list }

    func catalog(query: String, after: String?) async throws -> CatalogPage { CatalogPage(apps: [], total: 0, next: nil) }
    func accounts() async throws -> [ConnectedAccount] { lock.withLock { list } }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] {
        if lock.withLock({ failingTools.contains(app) }) { throw AppsFailure.unexpected }
        return lock.withLock { actions[app] ?? [] }
    }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        AppCallResult(isError: false, text: "")
    }
    func set(_ accounts: [ConnectedAccount]) { lock.withLock { list = accounts } }
}

private final class Log: @unchecked Sendable {
    let lock = NSLock()
    var signIn: [String] = []
    var connect: [String] = []
}

private func account(_ app: String, _ state: ConnectedAccount.State) -> ConnectedAccount {
    ConnectedAccount(id: "id_" + app, app: app, name: nil, state: state)
}

private func runner(_ service: ScriptedApps, catalog: [AppMention.Candidate], log: Log) -> AppToolRunner {
    AppToolRunner(
        service: { service }, catalog: catalog,
        suggest: { slug, _ in log.lock.withLock { log.connect.append(slug) } },
        signIn: { slug, name in log.lock.withLock { log.signIn.append("\(slug):\(name)") } })
}

@Test func signInSourceEdgesTests() async {
    let gmailAction = AppAction(slug: "gmail-send", name: "Send", description: "d", group: .crearYCambiar)
    let seed = [AppMention.Candidate(slug: "gmail", name: "Gmail"), AppMention.Candidate(slug: "slack_v2", name: "Slack")]

    // A current app in the catalog never nudges either way.
    let ok = ScriptedApps([account("slack_v2", .connected), account("gmail", .reconnect)])
    ok.actions["gmail"] = [gmailAction]
    let log = Log()
    let r = runner(ok, catalog: seed, log: log)
    await r.refresh()
    r.noteTurn("manda un slack")
    expect(log.signIn.isEmpty && log.connect.isEmpty, "16m-6 fix: una app al día que está en el catálogo no avisa")
    r.noteTurn("mira gmail")
    expect(r.specs(.en).allSatisfy { !$0.name.hasPrefix("gmail") }, "16m-6 fix: la caducada no ofrece herramientas aunque el servicio las liste")
    expectEq(log.signIn, ["gmail:Gmail"], "16m-6 fix: avisa de la caducada")

    // Two expired accounts: one notice each.
    let two = ScriptedApps([account("gmail", .reconnect), account("notion", .reconnect)])
    let logTwo = Log()
    let rTwo = runner(two, catalog: [], log: logTwo)
    await rTwo.refresh()
    rTwo.noteTurn("mira gmail")
    rTwo.noteTurn("y notion")
    rTwo.noteTurn("gmail otra vez")
    expectEq(logTwo.signIn, ["gmail:Gmail", "notion:Notion"], "16m-6 fix: un aviso por cuenta, una vez")

    // Reconnected: the next refresh forgets it.
    let back = ScriptedApps([account("gmail", .reconnect)])
    back.actions["gmail"] = [gmailAction]
    let logBack = Log()
    let rBack = runner(back, catalog: seed, log: logBack)
    await rBack.refresh()
    back.set([account("gmail", .connected)])
    await rBack.refresh()
    rBack.noteTurn("mira gmail")
    expect(logBack.signIn.isEmpty && logBack.connect.isEmpty, "16m-6 fix: tras reconectar no avisa")
    expect(!rBack.specs(.en).isEmpty, "16m-6 fix: y sus herramientas ya viajan")

    // "Connect" and "sign in" are separate once-per-launch sets.
    let flow = ScriptedApps([])
    let logFlow = Log()
    let rFlow = runner(flow, catalog: seed, log: logFlow)
    await rFlow.refresh()
    rFlow.noteTurn("mira gmail")
    expectEq(logFlow.connect, ["gmail"], "16m-6 fix: sin cuenta se ofrece conectar")
    flow.set([account("gmail", .reconnect)])
    await rFlow.refresh()
    rFlow.noteTurn("mira gmail")
    expectEq(logFlow.signIn, ["gmail:Gmail"], "16m-6 fix: haber ofrecido conectar no apaga el aviso de sesión")

    // Connected, but its tools failed to load: not "connect it".
    let broken = ScriptedApps([account("gmail", .connected)])
    broken.failingTools = ["gmail"]
    let logBroken = Log()
    let rBroken = runner(broken, catalog: seed, log: logBroken)
    await rBroken.refresh()
    rBroken.noteTurn("mira gmail")
    expect(logBroken.connect.isEmpty && logBroken.signIn.isEmpty,
           "16m-6 fix: una cuenta conectada cuyas herramientas fallaron no recibe «conectar»")

    // The name that reaches the card is display text: sanitized and short.
    let evil = ScriptedApps([account("evil\u{202E}gmail", .reconnect)])
    let logEvil = Log()
    let rEvil = runner(evil, catalog: [], log: logEvil)
    await rEvil.refresh()
    rEvil.noteTurn("mira evilgmail")
    expectEq(logEvil.signIn, ["evil\u{202E}gmail:Evilgmail"], "16m-6 fix: el nombre no lleva controles bidi")
    let long = ScriptedApps([account(String(repeating: "a", count: 200), .reconnect)])
    let logLong = Log()
    let rLong = runner(long, catalog: [], log: logLong)
    await rLong.refresh()
    rLong.noteTurn("mira " + String(repeating: "a", count: 40))
    let shown = logLong.signIn.first?.split(separator: ":").last.map(String.init) ?? ""
    expect(!shown.isEmpty && shown.count <= 40, "16m-6 fix: el nombre se acota a 40")
}

// MARK: - Reducer

@Test func signInReducerTableTests() {
    func machine(_ setup: [SessionEvent]) -> SessionMachine {
        var m = SessionMachine()
        for event in setup { _ = m.handle(event) }
        return m
    }
    let approval = ApprovalRequest(requestId: "r1", toolName: "Bash", summary: "ls", inputJSON: "{}")
    let states: [(String, [SessionEvent])] = [
        ("reposo", []),
        ("escuchando", [.pressed]),
        ("pensando", [.typedSubmitted]),
        ("respondiendo", [.typedSubmitted, .typedReplyStreaming]),
        ("error", [.voice(TurnSnapshot(state: .error, failure: .networkUnavailable))]),
        ("aprobación", [.job(.started(goal: "ordenar")), .job(.approvalRequested(approval))]),
        ("hint", [.tapped]),
    ]
    for (name, setup) in states {
        var m = machine(setup)
        let before = m.projection
        let effects = m.handle(.signInAppSuggested(slug: "gmail", name: "Gmail"))
        expectEq(m.projection.kind, before.kind, "16m-6 fix (\(name)): el kind no cambia")
        expectEq(m.projection.job, before.job, "16m-6 fix (\(name)): el encargo tampoco")
        expectEq(m.projection.approval, before.approval, "16m-6 fix (\(name)): ni la aprobación")
        expectEq(m.projection.holding, before.holding, "16m-6 fix (\(name)): ni el hold")
        expectEq(m.projection.notice, SessionCard.signInApp(slug: "gmail", name: "Gmail"), "16m-6 fix (\(name)): el aviso queda")
        expect(effects.contains(.scheduleNoticeExpiry(SessionMachine.noticeDelay)), "16m-6 fix (\(name)): con su plazo")
    }
}

@Test @MainActor func oldNoticeTimerDoesNotRetireTheNewNoticeTests() async {
    actor Gate {
        var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
        var count = 0
        func wait() async -> Int {
            count += 1
            let id = count
            await withCheckedContinuation { waiters[id] = $0 }
            return id
        }
        func open(_ id: Int) { waiters.removeValue(forKey: id)?.resume() }
        var started: Int { count }
    }
    let gate = Gate()
    // A sleep that ignores cancellation: the old timer wakes up anyway.
    let model = SessionModel(jobs: nil, approvals: nil, sleep: { _ in _ = await gate.wait() })
    model.send(.signInAppSuggested(slug: "gmail", name: "Gmail"))
    await pumpUntilAsync("16m-6 fix: primer plazo armado") { await gate.started == 1 }
    model.send(.signInAppSuggested(slug: "notion", name: "Notion"))
    await pumpUntilAsync("16m-6 fix: segundo plazo armado") { await gate.started == 2 }
    await gate.open(1)
    await settle(0.05)
    expectEq(model.projection.notice, SessionCard.signInApp(slug: "notion", name: "Notion"),
             "16m-6 fix: el plazo viejo no retira el aviso nuevo")
    await gate.open(2)
    await pumpUntil("16m-6 fix: el vigente sí lo retira") { model.projection.notice == nil }
}

// MARK: - Width

@Test @MainActor func wideCardReachTests() {
    let notch = NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 945,
        safeTop: 38, leftAuxWidth: 662, rightAuxWidth: 662))
    let table: [(IslandState.Size, CGFloat)] = [
        (.hidden, notch.width), (.pebble, notch.width), (.nudge, 492), (.bar, 320), (.card, 492),
    ]
    for (size, width) in table {
        expectEq(IslandChrome.width(for: size, notch: notch), width, "16m-6 fix: ancho de \(size)")
    }
    expect(IslandState.Size.allCases.count == table.count + 1, "16m-6 fix: la tabla cubre todos los tamaños menos el ancho")

    let kinds: [SessionKind] = [
        .idle, .hover, .listening, .processing(.pending), .processing(.thinking), .processing(.speaking),
        .processing(.completed), .processing(.subAgentRunning), .processing(.toolExecuting),
    ]
    let notices: [SessionCard?] = [
        nil, .holdHint, .couldntHear, .connectApp(slug: "s", name: "S"), .signInApp(slug: "s", name: "S"),
        .permission(.micDenied), .failure(.quotaExceeded), .failure(.networkUnavailable),
    ]
    for kind in kinds {
        for notice in notices {
            for update in [nil, "v1"] as [String?] {
                for hidden in [false, true] {
                    for front in [false, true] {
                        for errorText in [nil, "boom"] as [String?] {
                            var p = SessionProjection()
                            p.kind = kind
                            p.notice = notice
                            let state = IslandState.from(p, pebbleHidden: hidden, mainInFront: front,
                                                         errorText: errorText, update: update)
                            if state.size == .wideCard {
                                expectEq(state.line, .updateAvailable(tag: "v1"),
                                         "16m-6 fix: solo la actualización pide la forma ancha (\(kind), \(String(describing: notice)))")
                            }
                        }
                    }
                }
            }
        }
    }

    // A screen without a notch, and a narrow one: the shape and the canvas
    // still sit inside the screen.
    for width in [CGFloat(1024), 800] {
        let screen = ScreenShape(frame: CGRect(x: 0, y: 0, width: width, height: 700), visibleMaxY: 680,
                                 safeTop: 0, leftAuxWidth: 0, rightAuxWidth: 0)
        let flat = NotchGeometry.notch(on: screen)
        let canvas = IslandChrome.canvasFrame(for: flat)
        let shape = IslandChrome.shapeRect(IslandChrome.shapeSize(for: .wideCard, contentHeight: 120, notch: flat), notch: flat)
        expect(canvas.minX >= 0 && canvas.maxX <= width, "16m-6 fix: el lienzo cabe en una pantalla de \(width)")
        expect(shape.minX >= canvas.minX && shape.maxX <= canvas.maxX, "16m-6 fix: la forma ancha cabe en su lienzo (\(width))")
    }

    // Growing between the two card widths is a resize of an open panel, and
    // the pair-by-pair motion test (IslandUsefulTests) walks every Size.
    expect(!IslandMotion.steps(from: .card, to: .wideCard, reduceMotion: false).isEmpty, "16m-6 fix: card→wideCard anima")
    expect(IslandMotion.emptyPanel(from: .card, to: .wideCard) <= 0.04 + 1e-9, "16m-6 fix: y sin panel vacío")
}
