import Foundation

/// Validates endpoint URLs to restrict unencrypted HTTP to localhost only.
public enum EndpointPolicy: Sendable {
    /// Returns true if an endpoint URL is acceptable for requests.
    /// HTTPS is always acceptable.
    /// HTTP is only acceptable for localhost (127.0.0.1, ::1).
    public static func isAcceptable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }

        // HTTPS is always acceptable
        if scheme == "https" {
            return true
        }

        // HTTP is only acceptable for localhost
        if scheme == "http" {
            guard let host = url.host?.lowercased() else { return false }
            return isLocalhost(host)
        }

        // All other schemes rejected
        return false
    }

    private static func isLocalhost(_ host: String) -> Bool {
        // Check for common localhost representations
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
