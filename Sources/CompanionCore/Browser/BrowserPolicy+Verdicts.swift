import Foundation

extension BrowserPolicy {
    /// Acting inside a frame or on a link that belongs to another origin than
    /// the page hands control to a third party, so it asks. Without the page
    /// origin nothing can be compared and the answer is the cautious one.
    package static func clickVerdict(
        _ element: BrowserElement, said: String, pageOrigin: String? = nil
    ) -> HandsVerdict {
        if leavesPageOrigin(element, pageOrigin: pageOrigin) { return .ask }
        if let href = element.href {
            guard let pageOrigin, let target = URL(string: href), canonicalOrigin(of: target) == canonicalOrigin(pageOrigin)
            else { return .ask }
        }
        return HandsGate.clickVerdict(label: element.label, context: element.context, said: said)
    }

    package static func typeVerdict(
        _ element: BrowserElement, text: String, said: String, pageOrigin: String? = nil
    ) -> HandsVerdict {
        if isSensitive(element) { return .refuse(BridgeCode.secureField) }
        if leavesPageOrigin(element, pageOrigin: pageOrigin) { return .ask }
        return HandsGate.typeVerdict(text: text, said: said)
    }

    /// An option is a value typed in the page's words and, through the list's
    /// change handler, a button in disguise ("Bulk actions: Delete"), so it
    /// answers to both rules; the list's own label is the click's context.
    package static func selectVerdict(
        _ element: BrowserElement, option: String, said: String, pageOrigin: String? = nil
    ) -> HandsVerdict {
        let typed = typeVerdict(element, text: option, said: said, pageOrigin: pageOrigin)
        guard typed == .act else { return typed }
        return HandsGate.clickVerdict(label: option, context: element.label + " " + element.context, said: said)
    }

    /// Enter and Space activate what has the focus, so they are judged as a
    /// click on it. An Enter in any control of a form (a field, a checkbox, a
    /// date) submits it, so it is a click on the form's default button, and
    /// a field with no form or no submit button (a chat box that sends on
    /// Enter) asks. A key with no element goes into a focus nobody read:
    /// activating or erasing there asks. A key that writes or erases in a
    /// secret field is typing there, which is refused. Moving keys act,
    /// except an arrow on a list or a radio, which changes its value.
    package static func pressVerdict(
        key: String, element: BrowserElement?, said: String, pageOrigin: String? = nil
    ) -> HandsVerdict {
        if let element, leavesPageOrigin(element, pageOrigin: pageOrigin) { return .ask }
        guard let element else { return ["Enter", "Space", "Backspace", "Delete"].contains(key) ? .ask : .act }
        if pressWritesIntoSecret(key: key, element: element) { return .refuse(BridgeCode.secureField) }
        switch key {
        case "Enter":
            if isButton(element) { return clickVerdict(element, said: said, pageOrigin: pageOrigin) }
            if let submit = element.submit {
                return submit.isEmpty ? .ask : HandsGate.clickVerdict(label: submit, context: element.context, said: said)
            }
            return isTextField(element) ? .ask : clickVerdict(element, said: said, pageOrigin: pageOrigin)
        case "Space":
            return isTextField(element) ? .act : clickVerdict(element, said: said, pageOrigin: pageOrigin)
        case "Backspace", "Delete":
            return isTextField(element) ? .act : .ask
        case "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight":
            let changesValue = ["select", "radio"].contains(element.inputType?.lowercased() ?? "")
            return changesValue ? HandsGate.clickVerdict(label: element.label, context: element.context, said: said) : .act
        default:
            return .act
        }
    }

    /// Shared with the runner, which refuses these before spending a ticket.
    package static func pressWritesIntoSecret(key: String, element: BrowserElement) -> Bool {
        ["Space", "Backspace", "Delete"].contains(key) && isTextField(element) && isSensitive(element)
    }

    private static let textInputTypes: Set<String> = [
        "text", "search", "email", "url", "tel", "number", "password", "textarea",
    ]

    private static let buttonInputTypes: Set<String> = ["submit", "button", "image", "reset"]

    /// Judged by its own label: what Enter presses is the control itself.
    private static func isButton(_ element: BrowserElement) -> Bool {
        if let type = element.inputType?.lowercased() { return buttonInputTypes.contains(type) }
        return element.role == "button" || element.role == "link"
    }

    /// A contenteditable reports no input type, only the textbox role.
    private static func isTextField(_ element: BrowserElement) -> Bool {
        if let type = element.inputType?.lowercased() { return textInputTypes.contains(type) }
        return element.role == "textbox"
    }

    private static func leavesPageOrigin(_ element: BrowserElement, pageOrigin: String?) -> Bool {
        guard let frameOrigin = element.frameOrigin else { return false }
        guard let pageOrigin else { return true }
        return canonicalOrigin(frameOrigin) != canonicalOrigin(pageOrigin)
    }

    /// Only http(s) is navigable (`httpURL` refuses javascript:, data:, file:,
    /// chrome: first). Leaving the origin needs the user to have named the
    /// destination. Staying in it is not automatically harmless: a GET can
    /// change state (/logout, /account/delete?confirm=1), which would walk
    /// around the click gate. So it acts freely only when nothing new is
    /// requested (same path and query, a fragment change), and otherwise the
    /// path and query go through the destructive words.
    /// WHY a plain path change may act: refusing every same-site link would
    /// make the tool unusable, and a click on a link is already judged by
    /// its label; the finite word list is defence in depth, not a guarantee.
    package static func navigateVerdict(
        from origin: String?, currentURL: String?, to raw: String, said: String
    ) -> Result<HandsVerdict, ContractError> {
        let url: URL
        do {
            url = try ParentToolPolicy.httpURL(raw)
        } catch {
            return .failure(error)
        }
        if let origin, canonicalOrigin(of: url) == canonicalOrigin(origin) {
            return .success(sameOriginVerdict(url, currentURL: currentURL, said: said))
        }
        guard let host = url.host else { return .success(.ask) }
        return .success(ParentToolGate.saidIt(url, host: host, said: said) ? .act : .ask)
    }

    /// Without the current address nothing can be shown to be unchanged, so
    /// the words decide.
    package static func navigateVerdict(
        from origin: String?, to raw: String, said: String
    ) -> Result<HandsVerdict, ContractError> {
        navigateVerdict(from: origin, currentURL: nil, to: raw, said: said)
    }

    /// Stems matched inside the compacted path, for the camelCase and
    /// snake_case a URL uses ("deleteAccount", "sign_out") where whole words
    /// would miss them, plus acts the button families lack.
    private static let urlStems = [
        "delete", "remove", "logout", "signout", "unsubscribe", "deactivate", "revoke", "confirm",
        "destroy", "purge", "cancel", "disable", "terminate", "close",
    ]

    /// A scheme-relative or absolute "//host" inside a value: the shape of an
    /// open redirect parameter. Anchored so a "//" glued to a path segment
    /// ("/a//b") is not mistaken for one.
    private static let embeddedHost: NSRegularExpression? = {
        do {
            return try NSRegularExpression(
                pattern: "(?:^|[=&?#,;:(\\[]|[a-z][a-z0-9+.-]*:)//([^/?#&\\s\"'<>]+)", options: [.caseInsensitive])
        } catch {
            return nil
        }
    }()

    private static func sameOriginVerdict(_ url: URL, currentURL: String?, said: String) -> HandsVerdict {
        let current = currentURL.flatMap { URL(string: $0) }
        let pathAndQueryUnchanged = current.map { pathAndQuery(of: $0) == pathAndQuery(of: url) } ?? false
        let target = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let fragment = target?.percentEncodedFragment ?? ""
        if pathAndQueryUnchanged, current.flatMap(fragmentOf) ?? "" == fragment { return .act }
        var parts = [fragment]
        if !pathAndQueryUnchanged { parts += [target?.percentEncodedPath ?? url.path, target?.percentEncodedQuery ?? ""] }
        // An encoded word ("%64elete") must be judged as what the server will
        // see, and a double-encoded one as what a second decode would give.
        let views = parts.flatMap(decodedViews)
        if views.contains(where: { redirectsElsewhere($0, sameHost: url.host, said: said) }) { return .ask }
        let families = views.compactMap(HandsWords.destructiveFamily(of:))
        if !families.isEmpty { return families.allSatisfy { HandsWords.asks(family: $0, in: said) } ? .act : .ask }
        let spoken = HandsWords.words(said).replacingOccurrences(of: " ", with: "")
        let compacts = views.map { HandsWords.words($0).replacingOccurrences(of: " ", with: "") }
        return urlStems.contains { stem in !spoken.contains(stem) && compacts.contains { $0.contains(stem) } } ? .ask : .act
    }

    /// The raw text plus up to two percent-decodings, so single and double
    /// encoding both surface the real word.
    private static func decodedViews(_ raw: String) -> [String] {
        var views = [raw]
        for _ in 0..<2 {
            guard let last = views.last, let decoded = last.removingPercentEncoding, decoded != last else { break }
            views.append(decoded)
        }
        return views
    }

    private static func redirectsElsewhere(_ text: String, sameHost: String?, said: String) -> Bool {
        // Fail closed: if the pattern cannot compile, every value with "//" asks.
        guard let embeddedHost else { return text.contains("//") }
        let range = NSRange(text.startIndex..., in: text)
        return embeddedHost.matches(in: text, range: range).contains { match in
            guard let hostRange = Range(match.range(at: 1), in: text) else { return true }
            let authority = String(text[hostRange])
            let host = (authority.split(separator: "@").last.map(String.init) ?? authority)
                .split(separator: ":").first.map(String.init) ?? authority
            if host.lowercased() == sameHost?.lowercased() { return false }
            guard let target = URL(string: "https://" + host) else { return true }
            return !ParentToolGate.saidIt(target, host: host, said: said)
        }
    }

    private static func pathAndQuery(of url: URL) -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.path }
        return parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
    }

    private static func fragmentOf(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment
    }

    /// Whether two origins, or an origin and a full address, name the same
    /// place. The runner compares the tab's live address with the origin it
    /// read, so both sides go through the one normalization.
    package static func sameOrigin(_ first: String, _ second: String) -> Bool {
        canonicalOrigin(first) == canonicalOrigin(second)
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
