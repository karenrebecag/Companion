import CompanionCore
import Foundation

package struct WebResult: Sendable, Equatable {
    package var title: String
    package var url: String
    package var snippet: String

    package init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

/// Port so the provider can change without the tool noticing, and so a test
/// never goes out to a search engine.
package protocol WebSearching: Sendable {
    /// False means "do not offer this tool at all". A tool that is advertised
    /// and always fails is worse than a missing one: it captures the model's
    /// intent and then dies, and the model reports "I cannot search the web"
    /// instead of reaching for another route.
    var isConfigured: Bool { get }
    func search(_ query: String) async throws -> [WebResult]
}

/// Brave Search: its own index rather than a reseller of Google or Bing, which
/// fits an assistant that runs on your Mac; and the lowest latency of the
/// agent-oriented APIs, which is what decides it for a voice product.
package struct BraveWebSearch: WebSearching {
    package static let endpoint = "https://api.search.brave.com/res/v1/web/search"

    private let transport: any ChatTransport
    private let secrets: any SecretStore
    private let limit: Int

    package init(
        transport: any ChatTransport,
        secrets: any SecretStore,
        limit: Int = 6
    ) {
        self.transport = transport
        self.secrets = secrets
        self.limit = limit
    }

    package var isConfigured: Bool { key != nil }

    private var key: String? {
        let value: String?
        do {
            value = try secrets.read(.brave)
        } catch {
            return nil
        }
        guard let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    package func search(_ query: String) async throws -> [WebResult] {
        guard let key else { throw ChatError.unauthorized }
        var components = URLComponents(string: Self.endpoint)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(limit)),
        ]
        guard let url = components?.url, EndpointPolicy.isAcceptable(url) else {
            throw ChatError.unreachable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The header Brave documents. A key in the query string would end up
        // in logs and in every proxy along the way.
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else {
            throw ChatSSEAttempt.mapStatus(response.statusCode)
        }
        return Self.decode(data, limit: limit)
    }

    struct Payload: Decodable {
        struct Web: Decodable {
            struct Result: Decodable {
                let title: String?
                let url: String?
                let description: String?
            }
            let results: [Result]?
        }
        let web: Web?
    }

    static func decode(_ data: Data, limit: Int) -> [WebResult] {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            return []
        }
        return (payload.web?.results ?? []).prefix(limit).map { result in
            WebResult(
                title: result.title ?? "",
                url: result.url ?? "",
                snippet: result.description ?? "")
        }
    }
}
