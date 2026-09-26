import CompanionCore
import Foundation

/// Maps adapter errors to the failure the user actually sees. Without this the
/// session reports a generic drop and "no internet" reads as "voice died".
public enum VoiceFailureMapping: Sendable {
    public static func failure(for error: Error?) -> TurnFailure {
        guard let error else { return .sessionDropped }
        switch error {
        case let transport as VoiceTransportError:
            switch transport {
            case .unreachable, .timeout: return .networkUnavailable
            case .unauthorized, .closed: return .sessionDropped
            }
        case let chat as ChatError:
            switch chat {
            case .unreachable, .timeout: return .networkUnavailable
            case .httpStatus(429): return .quotaExceeded
            // `noProvider` es la escalera agotada, no la red caida. Decir "no
            // hay internet" con la red perfecta manda al usuario a arreglar lo
            // que no esta roto, y `noProviders` ya existia para esto.
            default: return .noProviders
            }
        case let url as URLError:
            return isOffline(url) ? .networkUnavailable : .sessionDropped
        default:
            if isQuota(error.localizedDescription) { return .quotaExceeded }
            return .sessionDropped
        }
    }

    public static func isQuota(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("credit") || lower.contains("quota")
            || lower.contains("billing") || lower.contains("insufficient")
    }

    private static func isOffline(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .timedOut,
             .internationalRoamingOff, .dataNotAllowed:
            return true
        default:
            return false
        }
    }
}
