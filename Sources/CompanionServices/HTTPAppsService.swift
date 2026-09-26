import CompanionCore
import Foundation

/// The companion-apps function over HTTPS (Wave 16k). The key rides only in
/// the Authorization header, never in a URL or a log.
public struct HTTPAppsService: AppsService {
    /// A catalog page is a few KB; anything this size is not the contract,
    /// and parsing it would stall the page.
    static let maxBody = 1024 * 1024

    private let base: URL
    private let key: String
    private let transport: any ChatTransport

    /// Security review 16k-1 (CRITICAL): the transport carries the redirect
    /// policy, so a redirect to another host never receives the key.
    public init(base: URL, key: String, transport: any ChatTransport = URLSessionChatTransport()) {
        self.base = base
        self.key = key
        self.transport = transport
    }

    public func catalog(query: String, after: String?) async throws -> CatalogPage {
        let (status, body) = try await send("api/apps", query: ["q": query, "after": after ?? "", "limit": "20"])
        return try AppsWire.catalog(status: status, body: body)
    }

    public func accounts() async throws -> [ConnectedAccount] {
        let (status, body) = try await send("api/accounts")
        return try AppsWire.accounts(status: status, body: body)
    }

    public func connectLink(app: String) async throws -> URL {
        let payload = try JSONSerialization.data(withJSONObject: ["app": app])
        let (status, body) = try await send("api/connect", method: "POST", body: payload)
        return try AppsWire.connectLink(status: status, body: body)
    }

    private func send(
        _ path: String, method: String = "GET", query: [String: String] = [:], body: Data? = nil
    ) async throws -> (Int, Data) {
        guard let url = AppsEndpoint.route(base, path, query: query) else { throw AppsFailure.unexpected }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.data(for: request)
        } catch {
            Log.app("apps: no answer from the function")
            throw AppsFailure.unreachable
        }
        guard data.count <= Self.maxBody else { throw AppsFailure.unexpected }
        // A refused redirect surfaces as the 3xx itself: not the contract.
        if !(200..<300).contains(http.statusCode) { Log.app("apps: function answered \(http.statusCode)") }
        return (http.statusCode, data)
    }
}
