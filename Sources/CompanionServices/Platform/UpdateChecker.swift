import CompanionCore
import Foundation

public struct UpdateInfo: Sendable, Equatable {
    public let version: SemanticVersion
    public let tag: String
    public let pageURL: URL
}

/// ADR 002: no update framework. Ask GitHub for the latest release, compare
/// against the built version, and point the user at the release page. Any
/// failure — no network, hostile payload, API change — is absolute silence:
/// an update check must never produce an error the user has to deal with.
public struct UpdateChecker: Sendable {
    public static let releaseAPI =
        URL(string: "https://api.github.com/repos/karenrebecag/Companion/releases/latest")!

    private let transport: any ChatTransport
    private let currentVersion: String
    private let now: @Sendable () -> Date
    private let lastCheck: @Sendable () -> Date?
    private let recordCheck: @Sendable (Date) -> Void

    public init(
        transport: any ChatTransport,
        currentVersion: String = Build.version,
        now: @escaping @Sendable () -> Date = { Date() },
        lastCheck: @escaping @Sendable () -> Date? = {
            UserDefaults.standard.object(forKey: cacheKey) as? Date
        },
        recordCheck: @escaping @Sendable (Date) -> Void = {
            UserDefaults.standard.set($0, forKey: cacheKey)
        }
    ) {
        self.transport = transport
        self.currentVersion = currentVersion
        self.now = now
        self.lastCheck = lastCheck
        self.recordCheck = recordCheck
    }

    public static let cacheKey = "companion.lastUpdateCheck"

    /// Launch path: at most one network hit per calendar day.
    public func checkIfDue() async -> UpdateInfo? {
        if let last = lastCheck(),
           Calendar.current.isDate(last, inSameDayAs: now()) {
            return nil
        }
        return await checkNow()
    }

    /// Settings path: the user asked, so the cache does not apply.
    public func checkNow() async -> UpdateInfo? {
        recordCheck(now())
        guard EndpointPolicy.isAcceptable(Self.releaseAPI) else { return nil }
        var request = URLRequest(url: Self.releaseAPI, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // User-facing silence, not log-facing: the failure is recorded and
        // the UI simply shows nothing.
        do {
            let (data, response) = try await transport.data(for: request)
            guard response.statusCode == 200 else {
                Log.app("update: releases API status \(response.statusCode)")
                return nil
            }
            return Self.parse(data, current: currentVersion)
        } catch {
            Log.app("update: check skipped (offline or API down)")
            return nil
        }
    }

    /// Pure so the fixtures test exactly what production runs.
    static func parse(_ data: Data, current: String) -> UpdateInfo? {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
        guard let object = parsed as? [String: Any],
              let tag = object["tag_name"] as? String,
              let page = object["html_url"] as? String,
              let pageURL = URL(string: page),
              isOurReleasePage(pageURL),
              let remote = SemanticVersion(tag),
              let local = SemanticVersion(current),
              remote > local
        else { return nil }
        return UpdateInfo(version: remote, tag: tag, pageURL: pageURL)
    }

    /// The page opens in the user's browser from a network answer, so it must
    /// be a release page of the repository `releaseAPI` names, on github.com:
    /// anything else in a hostile payload would be a phishing link one click
    /// from the island. Derived from the API URL so one literal owns the repo.
    static let releasePathPrefix: String = {
        // /repos/<owner>/<repo>/releases/latest -> /<owner>/<repo>/releases
        let parts = releaseAPI.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[0] == "repos" else { return "" }
        return "/" + [parts[1], parts[2], "releases"].joined(separator: "/")
    }()

    static func isOurReleasePage(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              !releasePathPrefix.isEmpty
        else { return false }
        // Traversal in any spelling: the check runs on the raw path, so an
        // encoded dot cannot slip past a decoded prefix match.
        let raw = url.path(percentEncoded: true).lowercased()
        guard !raw.contains(".."), !raw.contains("%2e") else { return false }
        let path = url.path.lowercased()
        let prefix = releasePathPrefix.lowercased()
        return path == prefix || path.hasPrefix(prefix + "/")
    }
}
