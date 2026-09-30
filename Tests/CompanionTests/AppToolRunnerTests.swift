import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// 16k-3: the connected apps' runner. What is pinned: the tool list follows
// the app the turn names (spec §5 context budget), a write without a grant
// never reaches the wire, a read never asks, and naming an unconnected app
// suggests connecting it exactly once.

private final class FakeAppsService: AppsService, @unchecked Sendable {
    let lock = NSLock()
    var calls: [(app: String, tool: String, approved: Bool)] = []
    var result = AppCallResult(isError: false, text: "sent")

    func catalog(query: String, after: String?) async throws -> CatalogPage {
        CatalogPage(apps: [], total: 0, next: nil)
    }

    func accounts() async throws -> [ConnectedAccount] {
        [ConnectedAccount(id: "apn_1", app: "slack_v2", name: "karen@x", state: .connected),
         ConnectedAccount(id: "apn_2", app: "gmail", name: nil, state: .reconnect)]
    }

    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }

    func tools(app: String) async throws -> [AppAction] {
        guard app == "slack_v2" else { return [] }
        return [
            AppAction(slug: "slack_v2-send-message", name: "Send Message",
                      description: "Send a message", group: .crearYCambiar,
                      schemaJSON: #"{"type":"object","properties":{"text":{"type":"string"}}}"#),
            AppAction(slug: "slack_v2-list-channels", name: "List Channels",
                      description: "List channels", group: .leer),
        ]
    }

    func disconnect(account: String) async throws {}

    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        record(app: app, tool: tool, approved: approved)
    }

    private func record(app: String, tool: String, approved: Bool) -> AppCallResult {
        lock.lock()
        defer { lock.unlock() }
        calls.append((app, tool, approved))
        return result
    }
}

@Test func appToolRunnerTests() async {
    let service = FakeAppsService()
    final class Suggested: @unchecked Sendable { var slugs: [String] = [] }
    let suggested = Suggested()
    let runner = AppToolRunner(
        service: { service },
        catalog: [AppMention.Candidate(slug: "notion", name: "Notion")],
        suggest: { slug, _ in suggested.slugs.append(slug) })
    await runner.refresh()

    // Before any turn is noted the whole connected set is offered: that is
    // the realtime session, whose list is fixed at open.
    expectEq(runner.specs(.es).count, 2, "runner: sin nota, todo lo conectado")
    expect(runner.specs(.es).allSatisfy { $0.name.hasPrefix("slack_v2-") },
           "runner: los nombres van tal cual, el slug ya los prefija")
    expect(runner.specs(.es).contains { $0.rawParametersJSON != nil },
           "runner: el schema crudo viaja en el spec")

    // The turn names the app: its tools travel. It does not: none do.
    runner.noteTurn("mandale un slack a Fer")
    expectEq(runner.specs(.es).count, 2, "runner: nombrada, sus tools")
    runner.noteTurn("dime la hora")
    expect(runner.specs(.es).isEmpty, "runner: sin nombrarla, cero tools de apps")
    expect(runner.handles("slack_v2-send-message"),
           "runner: handles no depende del filtro del turno")
    expect(!runner.handles("open_url"), "runner: lo que no es de una app no es suyo")

    // A write asks; a read does not. The request speaks human.
    let write = ToolCallRef(id: "1", name: "slack_v2-send-message",
                            arguments: #"{"text":"hola"}"#)
    let request = runner.approval(for: write, said: "manda hola")
    expectEq(request?.toolName, "app:slack_v2:slack_v2-send-message",
             "runner: la hoja recibe el prefijo app:")
    expect(request?.summary.contains("Send Message") == true,
           "runner: el resumen nombra la accion")
    let read = ToolCallRef(id: "2", name: "slack_v2-list-channels", arguments: "{}")
    expect(runner.approval(for: read, said: "") == nil, "runner: leer no pide hoja")

    // A write without its grant never reaches the wire.
    let refused = await runner.execute(
        name: "slack_v2-send-message", argumentsJSON: #"{"text":"hola"}"#)
    expect(!refused.ok, "runner: escribir sin grant se rechaza local")
    expect(service.calls.isEmpty, "runner: el rechazo no toca la funcion")

    if let request { runner.granted(request) }
    let sent = await runner.execute(
        name: "slack_v2-send-message", argumentsJSON: #"{"text":"hola"}"#)
    expect(sent.ok, "runner: con grant, corre")
    expectEq(service.calls.last?.approved, true, "runner: approved viaja true")

    // Reads run without a grant, and approved never lies.
    let listed = await runner.execute(name: "slack_v2-list-channels", argumentsJSON: "{}")
    expect(listed.ok, "runner: leer corre sin hoja")
    expectEq(service.calls.last?.approved, false, "runner: una lectura jamas dice approved")

    // The tool's own error comes back as words, not a crash.
    service.result = AppCallResult(isError: true, text: "channel_not_found")
    let failed = await runner.execute(name: "slack_v2-list-channels", argumentsJSON: "{}")
    expect(!failed.ok && failed.output.contains("channel_not_found"),
           "runner: el error de la tool vuelve como texto")

    // Naming an unconnected catalog app suggests connecting it, once.
    runner.noteTurn("ponlo en notion")
    runner.noteTurn("otra vez notion")
    expectEq(suggested.slugs, ["notion"], "runner: sugiere conectar una sola vez")

    // A new turn drops the old grant.
    runner.noteTurn("otra cosa")
    let stale = await runner.execute(
        name: "slack_v2-send-message", argumentsJSON: #"{"text":"x"}"#)
    expect(!stale.ok, "runner: el grant muere con el turno")

    // H1 (review 16k-3): the runner is shared by the three paths. The
    // narrowing a chat turn sets applies to ITS request only — specs()
    // consumes it — so a realtime session opened afterwards still gets
    // everything connected.
    runner.noteTurn("dime la hora")
    expect(runner.specs(.es).isEmpty, "runner: el turno que no nombra apps va vacio")
    expectEq(runner.specs(.es).count, 2,
             "runner: la lectura siguiente (una sesion realtime) vuelve a todo")

    // M1: a grant authorizes ONE call, not the rest of the session.
    runner.noteTurn("manda un slack")
    let again = ToolCallRef(id: "3", name: "slack_v2-send-message",
                            arguments: ##"{"text":"dos"}"##)
    if let request = runner.approval(for: again, said: "") { runner.granted(request) }
    service.result = AppCallResult(isError: false, text: "sent")
    let first = await runner.execute(
        name: "slack_v2-send-message", argumentsJSON: ##"{"text":"dos"}"##)
    expect(first.ok, "runner: la primera llamada con grant corre")
    let second = await runner.execute(
        name: "slack_v2-send-message", argumentsJSON: ##"{"text":"tres"}"##)
    expect(!second.ok, "runner: el grant se consume — la segunda vuelve a la hoja")
}

@Test func appToolRunnerSuggestsOnlyAfterLoadTests() async {
    // M2 (review 16k-3): before the first successful refresh the runner
    // cannot tell "not connected" from "not loaded yet" — a wrong card
    // would also burn the once-per-launch suggestion.
    let service = FakeAppsService()
    final class Suggested: @unchecked Sendable { var slugs: [String] = [] }
    let suggested = Suggested()
    let runner = AppToolRunner(
        service: { service },
        catalog: [AppMention.Candidate(slug: "slack_v2", name: "Slack")],
        suggest: { slug, _ in suggested.slugs.append(slug) })

    runner.noteTurn("manda un slack")
    expect(suggested.slugs.isEmpty, "runner: sin cache cargada no se sugiere nada")

    await runner.refresh()
    runner.noteTurn("manda un slack")
    expect(suggested.slugs.isEmpty,
           "runner: conectada tras la carga, tampoco — sus tools ya viajan")
}

@Test func compositeParentToolsTests() async {
    let service = FakeAppsService()
    let apps = AppToolRunner(service: { service }, catalog: [], suggest: nil)
    await apps.refresh()
    let parent = ParentToolRunner(workspace: NullWorkspace())
    let composite = CompositeParentTools([parent, apps])

    let names = composite.specs(.en).map(\.name)
    expect(names.contains("open_url") && names.contains("slack_v2-send-message"),
           "composite: las listas se suman")
    expect(composite.handles("slack_v2-list-channels"), "composite: rutea por handles")

    let outcome = await composite.execute(name: "slack_v2-list-channels", argumentsJSON: "{}")
    expect(outcome.ok, "composite: ejecuta en el runner correcto")
    expectEq(service.calls.count, 1, "composite: una llamada, un runner")

    let unknown = await composite.execute(name: "nope", argumentsJSON: "{}")
    expect(!unknown.ok, "composite: lo que nadie maneja falla con contrato")
}

private struct NullWorkspace: WorkspaceOpening {
    func openApplication(named name: String) async throws(ContractError) {
        throw ContractError.notFound("test workspace")
    }

    func open(_ url: URL) async throws(ContractError) {
        throw ContractError.notFound("test workspace")
    }

    func runningApplications() -> [String] { [] }
    func installedApplications() -> [String] { [] }
}

// 16m-7: the `@` selector offers the apps the runner already knows are connected.
@Test func appToolRunnerMentionCandidatesTests() async {
    let runner = AppToolRunner(service: { FakeAppsService() }, catalog: [], suggest: nil)
    expectEq(runner.connectedMentionCandidates().count, 0, "16m-7: antes de cargar no se inventa nada")
    await runner.refresh()
    let found = runner.connectedMentionCandidates()
    expectEq(found.map(\.kind), [.app], "16m-7: solo las conectadas, no la que pide reconectar")
    expectEq(found.map(\.id), ["slack_v2"], "16m-7: por su slug")
}
