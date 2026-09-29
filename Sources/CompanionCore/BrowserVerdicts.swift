import Foundation

extension BrowserPolicy {
    /// Acting inside a frame or on a link that belongs to another origin than
    /// the page hands control to a third party, so it asks. Without the page
    /// origin nothing can be compared and the answer is the cautious one.
    public static func clickVerdict(
        _ element: BrowserElement, said: String, pageOrigin: String? = nil
    ) -> HandsVerdict {
        if leavesPageOrigin(element, pageOrigin: pageOrigin) { return .ask }
        if let href = element.href {
            guard let pageOrigin, let target = URL(string: href), canonicalOrigin(of: target) == canonicalOrigin(pageOrigin)
            else { return .ask }
        }
        return HandsGate.clickVerdict(label: element.label, context: element.context, said: said)
    }

    public static func typeVerdict(
        _ element: BrowserElement, text: String, said: String, pageOrigin: String? = nil
    ) -> HandsVerdict {
        if isSensitive(element) { return .refuse(BridgeCode.secureField) }
        if leavesPageOrigin(element, pageOrigin: pageOrigin) { return .ask }
        return HandsGate.typeVerdict(text: text, said: said)
    }

    private static func leavesPageOrigin(_ element: BrowserElement, pageOrigin: String?) -> Bool {
        guard let frameOrigin = element.frameOrigin else { return false }
        guard let pageOrigin else { return true }
        return canonicalOrigin(frameOrigin) != canonicalOrigin(pageOrigin)
    }

    /// Only http(s) is navigable (`httpURL` refuses javascript:, data:, file:,
    /// chrome: first). Staying in the current origin is free; leaving it
    /// needs the user to have named the destination.
    public static func navigateVerdict(
        from origin: String?, to raw: String, said: String
    ) -> Result<HandsVerdict, ContractError> {
        let url: URL
        do {
            url = try ParentToolPolicy.httpURL(raw)
        } catch {
            return .failure(error)
        }
        if let origin, canonicalOrigin(of: url) == canonicalOrigin(origin) { return .success(.act) }
        guard let host = url.host else { return .success(.ask) }
        return .success(ParentToolGate.saidIt(url, host: host, said: said) ? .act : .ask)
    }

    /// scheme://host[:port] with the scheme's default port dropped, so an
    /// explicit :443 on https is the same origin as none.
    private static func canonicalOrigin(of url: URL) -> String {
        let scheme = (url.scheme ?? "").lowercased()
        var port = url.port
        if (scheme == "https" && port == 443) || (scheme == "http" && port == 80) { port = nil }
        return "\(scheme)://\((url.host ?? "").lowercased())\(port.map { ":\($0)" } ?? "")"
    }

    private static func canonicalOrigin(_ raw: String) -> String {
        if let url = URL(string: raw), url.scheme != nil, url.host != nil { return canonicalOrigin(of: url) }
        var text = raw.lowercased()
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
