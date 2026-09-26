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
