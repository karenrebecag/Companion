import CompanionCore
import Foundation

/// Exa's key, read the way Brave's is: a missing or blank value means the
/// provider is not configured, and a Keychain that throws counts as missing.
enum ExaKey {
    static func read(_ secrets: any SecretStore) -> String? {
        let value: String?
        do {
            value = try secrets.read(.exa)
        } catch {
            return nil
        }
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

enum ExaError: Error, Sendable, Equatable {
    /// A 200 whose body is not the documented shape. Failing closed: a
    /// half-parsed answer would be quoted as if it were the provider's.
    case malformedResponse
}

/// Exa search. Its key rides in `x-api-key`, never in the URL, for the same
/// reason Brave's rides in a header: a URL ends up in logs and proxies.
package struct ExaWebSearch: WebSearching {
    package static let endpoint = "https://api.exa.ai/search"
    /// Highlights are the passages that answer the query, so a number in the
    /// page arrives as text the model can quote.
    static let highlightCharacters = 800

    private let transport: any ChatTransport
    private let secrets: any SecretStore
    private let limit: Int

    package init(transport: any ChatTransport, secrets: any SecretStore, limit: Int = 6) {
        self.transport = transport
        self.secrets = secrets
        self.limit = limit
    }

    package var isConfigured: Bool { ExaKey.read(secrets) != nil }

    package func search(_ query: String) async throws -> [WebResult] {
        guard let key = ExaKey.read(secrets) else { throw ChatError.unauthorized }
        guard let url = URL(string: Self.endpoint), EndpointPolicy.isAcceptable(url) else {
            throw ChatError.unreachable
        }
        let body: [String: Any] = [
            "query": query,
            "numResults": limit,
            "contents": ["highlights": ["maxCharacters": Self.highlightCharacters]],
        ]
        let (data, response) = try await transport.data(
            for: ExaRequest.post(url, body: body, key: key))
        guard response.statusCode == 200 else {
            throw ChatSSEAttempt.mapStatus(response.statusCode)
        }
        return try Self.decode(data, limit: limit)
    }

    struct Payload: Decodable {
        struct Result: Decodable {
            let title: String?
            let url: String?
            let highlights: [String]?
        }
        let results: [Result]
    }

    static func decode(_ data: Data, limit: Int) throws -> [WebResult] {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ExaError.malformedResponse
        }
        return payload.results
            .compactMap { result -> WebResult? in
                // A result without a url cannot be cited, so it is not an answer.
                guard let url = result.url, !url.isEmpty else { return nil }
                return WebResult(
                    title: result.title ?? "",
                    url: url,
                    snippet: (result.highlights ?? []).joined(separator: " … "))
            }
            .prefix(limit)
            .map { $0 }
    }
}

/// Exa contents: the full text of a few pages. `fresh` asks for a live fetch
/// (maxAgeHours 0); otherwise Exa may answer from its cache.
package struct ExaWebReader: WebReading {
    package static let endpoint = "https://api.exa.ai/contents"
    /// The model's context is what this protects, not the network: a page
    /// past this length is cut here, and the cut is said.
    static let maxPageCharacters = 8_000
    static let maxURLs = 3

    private let transport: any ChatTransport
    private let secrets: any SecretStore

    package init(transport: any ChatTransport, secrets: any SecretStore) {
        self.transport = transport
        self.secrets = secrets
    }

    package var isConfigured: Bool { ExaKey.read(secrets) != nil }

    package func read(_ urls: [URL], fresh: Bool) async throws -> [WebPage] {
        guard let key = ExaKey.read(secrets) else { throw ChatError.unauthorized }
        guard let endpoint = URL(string: Self.endpoint), EndpointPolicy.isAcceptable(endpoint),
              !urls.isEmpty, urls.count <= Self.maxURLs
        else { throw ChatError.unreachable }
        var body: [String: Any] = [
            "urls": urls.map(\.absoluteString),
            "text": ["maxCharacters": Self.maxPageCharacters],
        ]
        if fresh { body["maxAgeHours"] = 0 }
        let (data, response) = try await transport.data(
            for: ExaRequest.post(endpoint, body: body, key: key))
        guard response.statusCode == 200 else {
            throw ChatSSEAttempt.mapStatus(response.statusCode)
        }
        return try Self.decode(data)
    }

    struct Payload: Decodable {
        struct Result: Decodable {
            let title: String?
            let url: String?
            let text: String?
        }
        let results: [Result]
    }

    static func decode(_ data: Data) throws -> [WebPage] {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ExaError.malformedResponse
        }
        return payload.results.compactMap { result -> WebPage? in
            guard let url = result.url, let text = result.text else { return nil }
            return WebPage(
                title: result.title ?? "",
                url: url,
                text: WebText.cap(text, to: maxPageCharacters))
        }
    }
}

/// Exa's wire format. Auth is a header, and the body is JSON.
enum ExaRequest {
    static func post(_ url: URL, body: [String: Any], key: String) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        return request
    }
}
