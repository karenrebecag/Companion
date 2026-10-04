import Foundation

/// Wave 16k (spec wave-16k-apps-conectadas.md): apps connected through the
/// companion-apps function. The function holds Pipedream's credentials; the
/// app only ever sees what these types carry.

package struct CatalogApp: Sendable, Equatable, Identifiable {
    package let slug: String
    package let name: String
    package let description: String?
    package let icon: URL?
    package var id: String { slug }

    package init(slug: String, name: String, description: String?, icon: URL?) {
        self.slug = slug
        self.name = name
        self.description = description
        self.icon = icon
    }
}

package struct CatalogPage: Sendable, Equatable {
    package let apps: [CatalogApp]
    package let total: Int
    package let next: String?

    package init(apps: [CatalogApp], total: Int, next: String?) {
        self.apps = apps
        self.total = total
        self.next = next
    }
}

package struct ConnectedAccount: Sendable, Equatable, Identifiable {
    package enum State: String, Sendable, Equatable {
        case connected, reconnect
    }

    package let id: String
    package let app: String
    package let name: String?
    package let state: State

    package init(id: String, app: String, name: String?, state: State) {
        self.id = id
        self.app = app
        self.name = name
        self.state = state
    }
}

/// One tool a connected app exposes through the function's `/api/tools`
/// (Wave 16k-2a, spec §9.2.1). `slug` is the wire's own tool name (also what
/// `/api/tools/call` will take in 16k-3); `name` is a readable label derived
/// from it.
package struct AppAction: Sendable, Equatable, Identifiable {
    package enum Group: String, Sendable, Hashable, CaseIterable {
        case leer, crearYCambiar, borrar
    }

    package let slug: String
    package let name: String
    package let description: String
    package let group: Group
    /// 16k-3: the tool's inputSchema as the wire sent it, re-serialized.
    /// Kept raw because the flat ToolProperty cannot express nesting; nil
    /// when the server declared none.
    package let schemaJSON: String?
    package var id: String { slug }

    package init(slug: String, name: String, description: String, group: Group,
                schemaJSON: String? = nil) {
        self.slug = slug
        self.name = name
        self.description = description
        self.group = group
        self.schemaJSON = schemaJSON
    }

    /// Server-declared read wins Leer; a destructive flag wins Borrar even
    /// next to a write kind; everything else — including no declaration at
    /// all — is Crear y cambiar, never Leer (spec §9.2.1). The function
    /// (companion-apps lib/mcp.mjs `classify()`) sends only "read"/"write"
    /// today; `destructive` is read defensively for when it grows a third.
    package static func classify(kind: String?, destructive: Bool) -> Group {
        if destructive || kind == "destructive" { return .borrar }
        if kind == "read" { return .leer }
        return .crearYCambiar
    }
}

package enum AppsFailure: Error, Sendable, Equatable {
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

/// What POST /api/call answers: the tool's own text, or its own error text
/// — either way words for the model, never a crash.
package struct AppCallResult: Sendable, Equatable {
    package let isError: Bool
    package let text: String

    package init(isError: Bool, text: String) {
        self.isError = isError
        self.text = text
    }
}

package protocol AppsService: Sendable {
    func catalog(query: String, after: String?) async throws -> CatalogPage
    func accounts() async throws -> [ConnectedAccount]
    func connectLink(app: String) async throws -> URL
    func tools(app: String) async throws -> [AppAction]
    /// `account` is the `ConnectedAccount.id`, not the app slug (spec §9.2.4).
    func disconnect(account: String) async throws
    /// 16k-3: runs one tool of a connected app. `approved` says the sheet
    /// was answered; the function refuses an unapproved write on its own.
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult
}

/// The function's address, as the user types it in.
package enum AppsEndpoint {
    /// https only (the app key rides every request), no credentials in the
    /// URL, and a bare base: the routes are ours to add.
    package static func validated(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        // Schemes are case-insensitive (RFC 3986 §3.1); rewriting to the
        // lowercase form keeps one stored spelling per function.
        guard var parts = URLComponents(string: trimmed), parts.scheme?.lowercased() == "https" else { return nil }
        parts.scheme = "https"
        guard let url = parts.url, url.scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty
        else { return nil }
        return url
    }

    /// `base` + route + non-empty query items, percent-encoded.
    package static func route(_ base: URL, _ path: String, query: [String: String] = [:]) -> URL? {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        let items = query.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }
}

/// Reads the function's `{ success, data, error, meta }` answers.
package enum AppsWire {
    package static func catalog(status: Int, body: Data) throws -> CatalogPage {
        let data = try payload(status: status, body: body)
        guard let apps = data["apps"] as? [[String: Any]] else { throw AppsFailure.unexpected }
        return CatalogPage(
            apps: apps.compactMap(app),
            total: data["total"] as? Int ?? apps.count,
            next: data["next"] as? String)
    }

    package static func accounts(status: Int, body: Data) throws -> [ConnectedAccount] {
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
    package static func connectLink(status: Int, body: Data) throws -> URL {
        let data = try payload(status: status, body: body)
        guard let text = data["url"] as? String, let url = URL(string: text),
              url.scheme == "https", url.host == "pipedream.com"
        else { throw AppsFailure.unexpected }
        return url
    }

    /// A realistic MCP app lists well under this; a hostile or broken one
    /// could try to hand the panel thousands (security review 16k-2a,
    /// MEDIUM) — capped here, once, rather than trusted to every renderer.
    package static let maxTools = 200

    /// Sorted alphabetically by display name so any caller that filters this
    /// list by group inherits the order without sorting again (audit §9.6).
    package static func tools(status: Int, body: Data) throws -> [AppAction] {
        let data = try payload(status: status, body: body)
        guard let tools = data["tools"] as? [[String: Any]] else { throw AppsFailure.unexpected }
        let sorted = tools.compactMap(action)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return Array(sorted.prefix(maxTools))
    }

    /// The server cuts at 20k (lib/mcp.mjs MAX_RESULT_CHARS); the same cap
    /// here means a misbehaving server still cannot flood the model.
    static let maxCallResult = 20_000

    /// POST /api/call (companion-apps api/call.mjs) answers `{isError,
    /// text}`: the tool's words either way, cut server-side and re-cut here.
    package static func callResult(status: Int, body: Data) throws -> AppCallResult {
        let data = try payload(status: status, body: body)
        guard let text = data["text"] as? String else { throw AppsFailure.unexpected }
        return AppCallResult(isError: data["isError"] as? Bool ?? false,
                             text: String(text.prefix(maxCallResult)))
    }

    /// DELETE /api/accounts?id=... (companion-apps api/accounts.mjs DELETE
    /// handler) answers `{ disconnected: id }`; returns that id so a caller
    /// can confirm it matches what it asked to remove.
    package static func disconnected(status: Int, body: Data) throws -> String {
        let data = try payload(status: status, body: body)
        guard let id = data["disconnected"] as? String, !id.isEmpty else { throw AppsFailure.unexpected }
        return id
    }

    package static func failure(status: Int, body: Data) -> AppsFailure {
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

    /// Icons load from Pipedream's own https hosts only, checked again here
    /// although the function already filters them. assets.pipedream.net is
    /// where the real catalog serves them from (seen live 2026-09-28).
    private static let iconHosts: Set<String> = ["pipedream.com", "assets.pipedream.net"]

    private static func icon(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https",
              let host = url.host, iconHosts.contains(host)
        else { return nil }
        return url
    }

    /// The function's own rule (companion-apps lib/validate.mjs TOOL),
    /// checked again here: a name outside it never becomes a spec, an
    /// approval key or a sheet subject (F-A, security review 16k-3).
    private static let toolName = "^[a-z0-9_]+-[a-z0-9_-]{1,120}$"

    private static func action(_ item: [String: Any]) -> AppAction? {
        guard let slug = item["name"] as? String,
              slug.range(of: toolName, options: .regularExpression) != nil
        else { return nil }
        let group = AppAction.classify(kind: item["kind"] as? String, destructive: item["destructive"] as? Bool ?? false)
        return AppAction(slug: slug, name: humanize(slug), description: item["description"] as? String ?? "", group: group,
                         schemaJSON: schema(item["inputSchema"]))
    }

    /// The inputSchema back to JSON, verbatim: the model reads it as its
    /// function parameters. Not valid JSON object → nil, never garbage.
    private static func schema(_ value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// "slack-send-message" -> "Slack Send Message": the wire has no
    /// separate display label, only the dashed tool name.
    private static func humanize(_ slug: String) -> String {
        slug.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
