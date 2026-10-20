import Darwin
import Foundation

/// Where `web_fetch` and `read_url` may reach. EndpointPolicy cannot serve
/// here: it lets http through to localhost because Ollama lives there, and a
/// page address comes from the model, so a prompt-injected one must not be
/// able to read the user's router, a local dev server or a cloud metadata
/// endpoint and carry the answer back into the conversation.
///
/// HACK: judges the literal host only. A public name that resolves to a
/// private address (DNS rebinding) passes. Resolve first and pin the
/// connection to the checked address when pages are fetched on a machine
/// that sits next to sensitive services.
package enum PageFetchPolicy: Sendable {
    package static func isAcceptable(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              var host = url.host?.lowercased(), !host.isEmpty
        else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return false
        }
        return !isPrivateLiteral(host)
    }

    /// inet_aton on purpose: it also reads the decimal, hex and octal spellings
    /// of an IPv4 address ("2130706433", "0x7f.1") that a URL parser hands over
    /// untouched and the system would still connect to.
    private static func isPrivateLiteral(_ host: String) -> Bool {
        var v4 = in_addr()
        if inet_aton(host, &v4) != 0 {
            return isPrivate(v4: UInt32(bigEndian: v4.s_addr))
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 {
            return isPrivate(v6: withUnsafeBytes(of: v6) { Array($0) })
        }
        return false
    }

    private static func isPrivate(v4 a: UInt32) -> Bool {
        let first = a >> 24
        let second = (a >> 16) & 0xFF
        switch first {
        case 0, 10, 127: return true
        case 100: return (64...127).contains(second)
        case 169: return second == 254
        case 172: return (16...31).contains(second)
        case 192: return second == 168 || (second == 0 && (a >> 8) & 0xFF == 0)
        default: return first >= 224
        }
    }

    private static func isPrivate(v6 b: [UInt8]) -> Bool {
        guard b.count == 16 else { return true }
        // :: and ::1
        if b.dropLast().allSatisfy({ $0 == 0 }) { return true }
        // IPv4-mapped (::ffff:a.b.c.d) is the IPv4 address in disguise.
        if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xFF, b[11] == 0xFF {
            let a = b[12...15].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return isPrivate(v4: a)
        }
        if b[0] & 0xFE == 0xFC { return true }
        return b[0] == 0xFE && b[1] & 0xC0 == 0x80
    }
}

/// A redirect is a new request the model never saw: every hop faces the same
/// policy as the first, or a public page could bounce the fetch inward.
package final class PageFetchRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    package func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, PageFetchPolicy.isAcceptable(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

package enum PageFetchSession {
    package static let shared = URLSession(configuration: NoStoreSession.configuration(), delegate: PageFetchRedirectDelegate(), delegateQueue: nil)
}
