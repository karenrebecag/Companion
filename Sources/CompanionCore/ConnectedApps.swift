import Foundation

/// Wave 16k (spec wave-16k-apps-conectadas.md): apps connected through the
/// companion-apps function. The function holds Pipedream's credentials; the
/// app only ever sees what these types carry.

public struct CatalogApp: Sendable, Equatable, Identifiable {
    public let slug: String
    public let name: String
    public let description: String?
    public let icon: URL?
    public var id: String { slug }

    public init(slug: String, name: String, description: String?, icon: URL?) {
        self.slug = slug
        self.name = name
        self.description = description
        self.icon = icon
    }
}

public struct CatalogPage: Sendable, Equatable {
    public let apps: [CatalogApp]
    public let total: Int
    public let next: String?

    public init(apps: [CatalogApp], total: Int, next: String?) {
        self.apps = apps
        self.total = total
        self.next = next
    }
}

public struct ConnectedAccount: Sendable, Equatable, Identifiable {
    public enum State: String, Sendable, Equatable {
        case connected, reconnect
    }

    public let id: String
    public let app: String
    public let name: String?
    public let state: State

    public init(id: String, app: String, name: String?, state: State) {
        self.id = id
        self.app = app
        self.name = name
        self.state = state
    }
}

public enum AppsFailure: Error, Sendable, Equatable {
    /// The function runs but lacks settings; it names them, never their values.
    case notConfigured([String])
    case unauthorized
    case rateLimited
    case invalidInput
    case notFound
    case approvalRequired
    case upstream
    /// No answer at all: no network, or the address is wrong.
    case unreachable
    /// An answer outside the contract.
    case unexpected
}

public protocol AppsService: Sendable {
    func catalog(query: String, after: String?) async throws -> CatalogPage
    func accounts() async throws -> [ConnectedAccount]
    func connectLink(app: String) async throws -> URL
}

/// The function's address, as the user types it in.
public enum AppsEndpoint {
    /// https only (the app key rides every request), no credentials in the
    /// URL, and a bare base: the routes are ours to add.
    public static func validated(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), url.scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty
        else { return nil }
        return url
    }

    /// `base` + route + non-empty query items, percent-encoded.
    public static func route(_ base: URL, _ path: String, query: [String: String] = [:]) -> URL? {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        let items = query.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }
}

/// Reads the function's `{ success, data, error, meta }` answers.
public enum AppsWire {
    public static func catalog(status: Int, body: Data) throws -> CatalogPage {
        let data = try payload(status: status, body: body)
        guard let apps = data["apps"] as? [[String: Any]] else { throw AppsFailure.unexpected }
        return CatalogPage(
            apps: apps.compactMap(app),
            total: data["total"] as? Int ?? apps.count,
            next: data["next"] as? String)
    }

    public static func accounts(status: Int, body: Data) throws -> [ConnectedAccount] {
        let data = try payload(status: status, body: body)
        guard let accounts = data["accounts"] as? [[String: Any]] else { throw AppsFailure.unexpected }
        return accounts.compactMap { item in
            guard let id = item["id"] as? String, let app = item["app"] as? String,
                  let raw = item["state"] as? String, let state = ConnectedAccount.State(rawValue: raw)
            else { return nil }
            return ConnectedAccount(id: id, app: app, name: item["name"] as? String, state: state)
        }
    }

    /// The Connect Link opens in the browser: only Pipedream's https page.
    public static func connectLink(status: Int, body: Data) throws -> URL {
        let data = try payload(status: status, body: body)
        guard let text = data["url"] as? String, let url = URL(string: text),
              url.scheme == "https", url.host == "pipedream.com"
        else { throw AppsFailure.unexpected }
        return url
    }

    public static func failure(status: Int, body: Data) -> AppsFailure {
        let object = json(body)
        switch object?["error"] as? String {
        case "not_configured":
            let meta = object?["meta"] as? [String: Any]
            return .notConfigured(meta?["missing"] as? [String] ?? [])
        case "unauthorized": return .unauthorized
        case "rate_limited": return .rateLimited
        case "invalid_input": return .invalidInput
        case "not_found": return .notFound
        case "approval_required": return .approvalRequired
        case "upstream_error", "tool_error": return .upstream
        default: return status == 401 ? .unauthorized : .unexpected
        }
    }

    private static func payload(status: Int, body: Data) throws -> [String: Any] {
        guard (200..<300).contains(status) else { throw failure(status: status, body: body) }
        let object = json(body)
        guard object?["success"] as? Bool == true, let data = object?["data"] as? [String: Any] else {
            throw AppsFailure.unexpected
        }
        return data
    }

    /// A body that is not a JSON object is simply not the contract.
    private static func json(_ body: Data) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: body) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func app(_ item: [String: Any]) -> CatalogApp? {
        guard let slug = item["slug"] as? String, !slug.isEmpty,
              let name = item["name"] as? String, !name.isEmpty
        else { return nil }
        return CatalogApp(slug: slug, name: name, description: item["description"] as? String,
                          icon: icon(item["icon"] as? String))
    }

    /// Icons load from Pipedream's own https host only, checked again here
    /// although the function already filters them.
    private static func icon(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https", url.host == "pipedream.com"
        else { return nil }
        return url
    }
}
