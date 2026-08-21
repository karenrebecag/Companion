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
              pageURL.scheme == "https",
              let remote = SemanticVersion(tag),
              let local = SemanticVersion(current),
              remote > local
        else { return nil }
        return UpdateInfo(version: remote, tag: tag, pageURL: pageURL)
    }
}
