import CompanionCore
import Foundation
import Testing

// Wave 16k-3 (spec §2.5): the connected apps' tools reach the brain in both
// modes, writes pass the approval sheet, and naming an unconnected app
// raises the "Conectar X" card. This file pins the Core half: the wire
// keeps the schema, the mention matcher, the sheet copy, and the island
// plumbing for the connect card.

private func data(_ json: String) -> Data { Data(json.utf8) }

@Test func appToolsWireTests() throws {
    // The function sends each tool's inputSchema; the spec travels whole to
    // the model, so the wire must keep it, not flatten it away.
    let tools = try AppsWire.tools(status: 200, body: data("""
    {"success":true,"data":{"tools":[
      {"name":"slack_v2-send-message","description":"Send a message","kind":"write",
       "inputSchema":{"type":"object","properties":{"channel":{"type":"string"}},"required":["channel"]}},
      {"name":"slack_v2-list-channels","description":"List channels","kind":"read"}
    ]}}
    """))
    expectEq(tools.count, 2, "wire: dos tools")
    let send = tools.first { $0.slug == "slack_v2-send-message" }
    let list = tools.first { $0.slug == "slack_v2-list-channels" }
    expect(send?.schemaJSON?.contains("\"channel\"") == true,
           "wire: el inputSchema viaja entero como JSON")
    expect(list?.schemaJSON == nil, "wire: sin schema declarado, nil")

    // POST /api/call answers {isError, text}.
    let result = try AppsWire.callResult(status: 200, body: data(
        #"{"success":true,"data":{"isError":false,"text":"sent"}}"#))
    expectEq(result, AppCallResult(isError: false, text: "sent"), "wire: resultado de call")
    #expect(throws: AppsFailure.approvalRequired) {
        try AppsWire.callResult(status: 403, body: data(
            #"{"success":false,"error":"approval_required"}"#))
    }
}

@Test func appsWireIconHostTests() throws {
    // Live 2026-09-28: Pipedream serves icons from assets.pipedream.net,
    // not pipedream.com — the old filter dropped every real icon.
    let page = try AppsWire.catalog(status: 200, body: data("""
    {"success":true,"data":{"apps":[
      {"slug":"slack","name":"Slack","icon":"https://assets.pipedream.net/icons/slack.svg"}
    ],"total":1,"next":null}}
    """))
    expectEq(page.apps[0].icon?.host, "assets.pipedream.net",
             "wire: los iconos reales de Pipedream pasan el filtro")
}

@Test func appMentionTests() {
    let connected = [AppMention.Candidate(slug: "slack_v2", name: "Slack")]
    let catalog = [AppMention.Candidate(slug: "notion", name: "Notion"),
                   AppMention.Candidate(slug: "google_calendar", name: "Google Calendar")]

    expectEq(AppMention.match("mandale un slack a Fer", in: connected), "slack_v2",
             "mention: nombre en minusculas dentro de la frase")
    expectEq(AppMention.match("revisa mi SLACK", in: connected), "slack_v2",
             "mention: sin distinguir mayusculas")
    expect(AppMention.match("abre la terminal", in: connected) == nil,
           "mention: sin nombre no hay match")
    // "slackline" is not Slack: the name matches on word boundaries.
    expect(AppMention.match("practico slackline", in: connected) == nil,
           "mention: el nombre no matchea dentro de otra palabra")
    expectEq(AppMention.match("agendalo en google calendar", in: catalog), "google_calendar",
             "mention: nombre de dos palabras")
    expectEq(AppMention.match("ponlo en notion", in: catalog), "notion",
             "mention: match sobre el catalogo para sugerir conectar")
}

@Test func toolSpecRawSchemaTests() throws {
    func parameters(_ spec: ToolSpec) throws -> [String: Any]? {
        let object = try JSONSerialization.jsonObject(
            with: Data(spec.encodeRealtime().utf8)) as? [String: Any]
        return object?["parameters"] as? [String: Any]
    }

    // A Pipedream schema has nesting the flat ToolProperty cannot express:
    // the raw JSON wins when present, the flat encoding stays for the rest.
    let raw = #"{"type":"object","properties":{"a":{"type":"object","properties":{"b":{"type":"string"}}}},"required":["a"]}"#
    let spec = ToolSpec(name: "slack_v2-send-message", description: "Send",
                        properties: [], required: [], rawParametersJSON: raw)
    let nested = try parameters(spec)?["properties"] as? [String: Any]
    expect((nested?["a"] as? [String: Any])?["properties"] != nil,
           "spec: el schema anidado viaja tal cual al modelo")

    let flat = ToolSpec(name: "x", description: "d",
                        properties: [ToolProperty(name: "p", type: "string", description: "q")],
                        required: ["p"])
    expect(((try parameters(flat)?["properties"] as? [String: Any])?["p"]) != nil,
           "spec: sin raw, la codificacion plana sigue igual")

    // A raw string that does not parse falls back to the flat encoding
    // instead of sending garbage.
    let broken = ToolSpec(name: "y", description: "d", properties: [], required: [],
                          rawParametersJSON: "{not json")
    expect(try parameters(broken)?["type"] as? String == "object",
           "spec: raw roto cae al plano, nunca revienta")
}

@Test func approvalCopyAppToolTests() {
    // The runner mints "app:<slug>:<tool>" requests; the sheet shows the
    // human summary the runner built and the arguments as the preview.
    let display = ApprovalCopy.display(
        for: ApprovalRequest(
            requestId: "1", toolName: "app:slack_v2:slack_v2-send-message",
            summary: "Send Message · Slack",
            inputJSON: ##"{"channel":"#general","text":"hola"}"##),
        language: .es)
    expectEq(display.subject, "Send Message · Slack", "app tool: el resumen humano es el sujeto")
    expect(display.preview?.contains("#general") == true,
           "app tool: los argumentos completos son el preview — es lo que corre")
    expect(!display.showsRemember,
           "app tool: sin ApprovalKey no se ofrece recordar (nunca una promesa vacia)")
}

@Test func appToolHardeningTests() throws {
    // F-A: a tool name outside the function's own charset never enters the
    // catalog — it would become a spec, a grant key and a sheet subject.
    let tools = try AppsWire.tools(status: 200, body: data("""
    {"success":true,"data":{"tools":[
      {"name":"slack_v2-send-message","description":"ok","kind":"write"},
      {"name":"slack_v2-x:evil","description":"colon smuggler","kind":"read"},
      {"name":"Slack Send","description":"spaces","kind":"read"}
    ]}}
    """))
    expectEq(tools.map { $0.slug }, ["slack_v2-send-message"],
             "wire: nombres fuera del charset del contrato se descartan")

    // F-E: the client re-cuts a result even if the server forgot to.
    let flood = String(repeating: "a", count: 30_000)
    let cut = try AppsWire.callResult(status: 200, body: data(
        #"{"success":true,"data":{"isError":false,"text":"\#(flood)"}}"#))
    expectEq(cut.text.count, 20_000, "wire: el resultado se corta tambien del lado cliente")

    // F-G: an app sheet belongs to the parent's turn — a switched turn
    // must drop it, same as open_url's.
    expect(ParentTool.ownsRequest("app:slack_v2:slack_v2-send-message"),
           "ownsRequest: las hojas de apps se descartan con su turno")
    expect(!ParentTool.ownsRequest("bridge_session"),
           "ownsRequest: la del puente sigue sin ser del padre")

    // F-F: bidi and control scalars leave the preview; layout stays.
    let display = ApprovalCopy.display(
        for: ApprovalRequest(
            requestId: "1", toolName: "app:slack_v2:slack_v2-send-message",
            summary: "Send Message · Slack",
            inputJSON: "{\"text\":\"a\u{202E}evil\u{202C}b\nc\"}"),
        language: .es)
    expect(display.preview?.contains("\u{202E}") == false,
           "preview: los scalars bidi no llegan a la hoja")
    expect(display.preview?.contains("\n") == true, "preview: el salto de linea queda")
}

@Test func connectAppCardTests() {
    // The event raises a fading card with the app's name and a way to the
    // Apps page; answering nothing lets it expire like couldntHear.
    var machine = SessionMachine()
    let effects = machine.handle(.connectAppSuggested(slug: "notion", name: "Notion"))
    expectEq(machine.projection.notice, SessionCard.connectApp(slug: "notion", name: "Notion"),
             "card: el evento levanta la tarjeta")
    expect(effects.contains(.scheduleNoticeExpiry(SessionMachine.noticeDelay)),
           "card: la tarjeta se va sola, como couldntHear")
    _ = machine.handle(.noticeExpired)
    expect(machine.projection.notice == nil, "card: expira")

    var projection = SessionProjection()
    projection.notice = .connectApp(slug: "notion", name: "Notion")
    let card = IslandState.from(projection, pebbleHidden: false)
    expectEq(card.size, IslandState.Size.card, "card: tamano tarjeta")
    expectEq(card.line, IslandState.Line.connectApp(slug: "notion", name: "Notion"),
             "card: la linea nombra la app")
    expectEq(card.action, IslandState.Action.openApps(slug: "notion"),
             "card: la salida abre la pagina Apps")
}
