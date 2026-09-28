import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Security review 16k-1 (CRITICAL): the function's key rides every request,
// so a redirect to another host must not carry it there; and an answer too
// big to be the contract is refused before it is parsed.

private final class AppsStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var foreignAuthorization: [String?] = []
    nonisolated(unsafe) static var bigBody = false
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool {
        ["function.test", "evil.test"].contains(request.url?.host ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        if url.host == "function.test", !Self.bigBody {
            let moved = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                                        headerFields: ["Location": "https://evil.test/steal"])!
            client.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://evil.test/steal")!),
                               redirectResponse: moved)
            // A refused redirect leaves the 302 as the answer.
            client.urlProtocol(self, didReceive: moved, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(self)
            return
        }
        if url.host == "evil.test" {
            Self.lock.withLock { Self.foreignAuthorization.append(request.value(forHTTPHeaderField: "Authorization")) }
        }
        let body = Self.bigBody
            ? Data(repeating: 0x20, count: HTTPAppsService.maxBody + 1)
            : Data(#"{"success":true,"data":{"accounts":[]}}"#.utf8)
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client.urlProtocol(self, didReceive: ok, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: body)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedService() -> HTTPAppsService {
    HTTPAppsService(
        base: URL(string: "https://function.test")!, key: String(repeating: "k", count: 64),
        transport: URLSessionChatTransport(protocolClasses: [AppsStub.self]))
}

@Test func httpAppsServiceKeepsTheKeyHome() async {
    AppsStub.lock.withLock { AppsStub.bigBody = false }
    await #expect(throws: (any Error).self) { _ = try await stubbedService().accounts() }
    #expect(AppsStub.lock.withLock { AppsStub.foreignAuthorization }.isEmpty,
            "a redirect to another host never reaches it, key or not")
}

@Test func httpAppsServiceRefusesAnOversizedAnswer() async {
    AppsStub.lock.withLock { AppsStub.bigBody = true }
    await #expect(throws: AppsFailure.unexpected) { _ = try await stubbedService().accounts() }
    AppsStub.lock.withLock { AppsStub.bigBody = false }
}

// Wave 16k-2a: tools(app:) follows the same send() path, scripted here
// instead of through AppsStub since it only needs a POST body round trip.
@Test func httpAppsServiceListsTools() async throws {
    let transport = ScriptedTransport()
    transport.stub(url: "https://function.test/api/tools", ScriptedReply(
        status: 200,
        body: Data(#"""
        {"success":true,"data":{"tools":[
          {"name":"slack-list-channels","description":"List channels","kind":"read"}
        ]}}
        """#.utf8)))
    let service = HTTPAppsService(
        base: URL(string: "https://function.test")!, key: String(repeating: "k", count: 64), transport: transport)
    let actions = try await service.tools(app: "slack")
    #expect(actions == [AppAction(slug: "slack-list-channels", name: "Slack List Channels",
                                   description: "List channels", group: .leer)])
    let sent = try #require(transport.requests.first)
    #expect(sent.httpMethod == "POST")
    #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer \(String(repeating: "k", count: 64))")
    let body = try #require(sent.httpBody)
    let sentApp = try JSONSerialization.jsonObject(with: body) as? [String: String]
    #expect(sentApp?["app"] == "slack")
}

// Wave 16k-2c: disconnect(account:) follows the same send() path as the
// rest of the service, pinned to DELETE /api/accounts?id=... (16k-0's
// api/accounts.mjs DELETE handler).
@Test func httpAppsServiceDisconnectsAnAccount() async throws {
    let transport = ScriptedTransport()
    transport.stub(url: "https://function.test/api/accounts?id=apn_1", ScriptedReply(
        status: 200, body: Data(#"{"success":true,"data":{"disconnected":"apn_1"}}"#.utf8)))
    let service = HTTPAppsService(
        base: URL(string: "https://function.test")!, key: String(repeating: "k", count: 64), transport: transport)
    try await service.disconnect(account: "apn_1")
    let sent = try #require(transport.requests.first)
    #expect(sent.httpMethod == "DELETE")
    #expect(sent.url?.absoluteString == "https://function.test/api/accounts?id=apn_1")
    #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer \(String(repeating: "k", count: 64))")
}
