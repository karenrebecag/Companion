import CompanionCore
import Foundation
import Testing

// Wave 16k-1 (spec wave-16k-apps-conectadas.md): what the companion-apps
// function answers, read strictly. Its contract is its README.

private func data(_ json: String) -> Data { Data(json.utf8) }

@Test func connectedAppsTests() throws {
    let page = try AppsWire.catalog(status: 200, body: data("""
    {"success":true,"data":{"apps":[
      {"slug":"slack","name":"Slack","description":"Send messages","icon":"https://pipedream.com/s.v0/app_1/logo/orig"},
      {"slug":"gmail","name":"Gmail","description":null,"icon":"http://evil.example/x.png"}
    ],"total":1734,"next":"c2"}}
    """))
    #expect(page.apps.map(\.slug) == ["slack", "gmail"])
    #expect(page.total == 1734)
    #expect(page.next == "c2")
    #expect(page.apps[0].icon?.host == "pipedream.com")
    #expect(page.apps[1].icon == nil, "an icon off pipedream.com is not loaded")
    #expect(page.apps[1].description == nil)

    let accounts = try AppsWire.accounts(status: 200, body: data("""
    {"success":true,"data":{"accounts":[
      {"id":"apn_1","app":"slack","name":"karen@x","state":"connected"},
      {"id":"apn_2","app":"gmail","name":null,"state":"reconnect"}
    ]}}
    """))
    #expect(accounts == [
        ConnectedAccount(id: "apn_1", app: "slack", name: "karen@x", state: .connected),
        ConnectedAccount(id: "apn_2", app: "gmail", name: nil, state: .reconnect),
    ])

    let link = try AppsWire.connectLink(status: 200, body: data("""
    {"success":true,"data":{"url":"https://pipedream.com/_static/connect.html?token=ctok_1&app=slack","expiresAt":null}}
    """))
    #expect(link.host == "pipedream.com")
    // The app opens this in the browser: anything but Pipedream's https page is refused.
    #expect(throws: AppsFailure.unexpected) {
        try AppsWire.connectLink(status: 200, body: data(#"{"success":true,"data":{"url":"file:///etc/passwd"}}"#))
    }
}

@Test func connectedAppsFailures() {
    #expect(AppsWire.failure(status: 503, body: data(
        #"{"success":false,"error":"not_configured","meta":{"missing":["PIPEDREAM_CLIENT_ID"]}}"#))
        == .notConfigured(["PIPEDREAM_CLIENT_ID"]))
    #expect(AppsWire.failure(status: 401, body: data(#"{"success":false,"error":"unauthorized"}"#)) == .unauthorized)
    #expect(AppsWire.failure(status: 429, body: data(#"{"success":false,"error":"rate_limited"}"#)) == .rateLimited)
    #expect(AppsWire.failure(status: 502, body: data(#"{"success":false,"error":"upstream_error"}"#)) == .upstream)
    #expect(AppsWire.failure(status: 500, body: data("<html>")) == .unexpected)
    #expect(throws: AppsFailure.unauthorized) {
        try AppsWire.catalog(status: 401, body: data(#"{"success":false,"error":"unauthorized"}"#))
    }
}

// Wave 16k-2a: /api/tools marks each tool "read" or "write" (companion-apps
// lib/mcp.mjs classify()); the app itself decides the third bucket from a
// destructive flag the function does not send yet but the wire tolerates.
@Test func appActionGroupMapping() {
    #expect(AppAction.classify(kind: "read", destructive: false) == .leer)
    #expect(AppAction.classify(kind: nil, destructive: false) == .crearYCambiar, "undeclared never reads")
    #expect(AppAction.classify(kind: "write", destructive: false) == .crearYCambiar)
    #expect(AppAction.classify(kind: "write", destructive: true) == .borrar, "destructive beats write when both appear")
    #expect(AppAction.classify(kind: "destructive", destructive: false) == .borrar)
    #expect(AppAction.classify(kind: "read", destructive: true) == .borrar, "destructive beats a stray read too")
}

@Test func appsWireToolsParsing() throws {
    let actions = try AppsWire.tools(status: 200, body: data("""
    {"success":true,"data":{"tools":[
      {"name":"slack-send-message","description":"Send a message","kind":"write"},
      {"name":"slack-list-channels","description":"List channels","kind":"read"},
      {"name":"slack-archive-channel","description":"Archive a channel","kind":"write","destructive":true},
      {"name":"slack-add-reaction","description":"React to a message"}
    ]}}
    """))
    #expect(actions.map(\.slug) == [
        "slack-add-reaction", "slack-archive-channel", "slack-list-channels", "slack-send-message",
    ], "alphabetical order across the whole answer")
    #expect(actions.first { $0.slug == "slack-add-reaction" }?.group == .crearYCambiar, "no kind at all never reads")
    #expect(actions.first { $0.slug == "slack-list-channels" }?.group == .leer)
    #expect(actions.first { $0.slug == "slack-archive-channel" }?.group == .borrar)
    #expect(actions.first { $0.slug == "slack-send-message" }?.group == .crearYCambiar)
    #expect(actions.first { $0.slug == "slack-send-message" }?.name == "Slack Send Message")

    let empty = try AppsWire.tools(status: 200, body: data(#"{"success":true,"data":{"tools":[]}}"#))
    #expect(empty.isEmpty)

    #expect(throws: AppsFailure.invalidInput) {
        try AppsWire.tools(status: 400, body: data(#"{"success":false,"error":"invalid_input"}"#))
    }
    #expect(throws: AppsFailure.unauthorized) {
        try AppsWire.tools(status: 401, body: data(#"{"success":false,"error":"unauthorized"}"#))
    }
}

// Security review 16k-2a (MEDIUM): a misbehaving or hostile MCP app could
// list far more tools than any real app does; the parser caps it so the
// panel never has to render (or lazily hold) an unbounded list.
@Test func appsWireToolsCapsAtTwoHundred() throws {
    let items = (0..<201).map { #"{"name":"slack-tool-\#($0)","description":"","kind":"read"}"# }
    let body = data(#"{"success":true,"data":{"tools":["# + items.joined(separator: ",") + "]}}")
    let actions = try AppsWire.tools(status: 200, body: body)
    #expect(actions.count == 200, "201 sent, only 200 parsed")
}

@Test func connectedAppsEndpoint() {
    #expect(AppsEndpoint.validated("https://companion-apps.vercel.app")?.absoluteString
        == "https://companion-apps.vercel.app")
    #expect(AppsEndpoint.validated("  https://companion-apps.vercel.app/  ")?.absoluteString
        == "https://companion-apps.vercel.app", "trimmed, no trailing slash")
    #expect(AppsEndpoint.validated("http://companion-apps.vercel.app") == nil, "the key never travels in clear")
    #expect(AppsEndpoint.validated("https://user:pw@x.vercel.app") == nil)
    #expect(AppsEndpoint.validated("https://x.vercel.app/api?q=1") == nil, "a base, not a route")
    #expect(AppsEndpoint.validated("nope") == nil)
    let base = URL(string: "https://x.vercel.app")!
    #expect(AppsEndpoint.route(base, "api/apps", query: ["q": "sl ack", "after": ""])?.absoluteString
        == "https://x.vercel.app/api/apps?q=sl%20ack")
}
