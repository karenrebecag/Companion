import Foundation

/// Validates redirect targets to prevent Authorization headers from leaking
/// to cross-host or downgraded connections.
public enum RedirectPolicy: Sendable {
    /// Returns true if a redirect from `from` to `to` is safe.
    /// A redirect is safe only if:
    /// - Both URLs have the same host
    /// - Both URLs have the same port (or no explicit port)
    /// - Both URLs have the same scheme
    /// - No downgrade from https to http
    public static func allows(from: URL, to: URL) -> Bool {
        // Extract scheme, host, and port carefully
        guard let fromScheme = from.scheme?.lowercased(),
              let fromHost = from.host?.lowercased(),
              let toScheme = to.scheme?.lowercased(),
              let toHost = to.host?.lowercased() else {
            return false
        }

        // Hosts must match exactly
        guard fromHost == toHost else { return false }

        // Schemes must match (no downgrade from https to http)
        guard fromScheme == toScheme else { return false }

        // Ports must match. URL.port returns nil if no explicit port, which means
        // the default port for the scheme. Compare explicitly.
        let fromPort = from.port ?? defaultPort(for: fromScheme)
        let toPort = to.port ?? defaultPort(for: toScheme)
        guard fromPort == toPort else { return false }

        return true
    }

    private static func defaultPort(for scheme: String) -> Int {
        switch scheme {
        case "http": return 80
        case "https": return 443
        default: return -1
        }
    }
}
