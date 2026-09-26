import Foundation

/// Validators for the parent's tools, ported from Relay's `contracts/mod.rs`
/// with the two fixes its review found: `home` is canonicalized once (a home
/// on a network volume used to deny everything) and hidden components are
/// checked again after symlinks resolve (`~/dotfiles → ~/.config`).
public enum ParentToolPolicy {
    public static let maxAppNameLength = 64
    /// PATH_MAX. Checked before any parsing or disk walk.
    public static let maxInputLength = 4096
    /// What LaunchServices EXECUTES rather than displays: an `.app` launches,
    /// a `.command`/`.tool`/`.terminal` runs in Terminal, a `.workflow` or
    /// script runs, and a `.webloc`/`.inetloc` follows the URL stored inside
    /// the file — a second door to `file://` or `javascript:` that `httpURL`
    /// never sees. `open_file` is for documents and folders; opening an app
    /// has its own tool with its own name check.
    static let launcherExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "workflow", "action",
        "scpt", "scptd", "applescript", "webloc", "inetloc", "fileloc",
    ]

    public static func appName(_ raw: String) throws(ContractError) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        guard !name.isEmpty else { throw .invalidArgs("app name is empty") }
        guard name.count <= maxAppNameLength else {
            throw .invalidArgs("app name is longer than \(maxAppNameLength) characters")
        }
        let forbidden: Set<Character> = ["/", "\\", ";"]
        for ch in name where forbidden.contains(ch) || ch.isNewline || isControl(ch) {
            throw .invalidArgs("app name contains an invalid character")
        }
        return name
    }

    /// `EndpointPolicy` governs OUR requests; this governs the user's browser,
    /// where http to any host is legitimate ("open http://my-router").
    public static func httpURL(_ raw: String) throws(ContractError) -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .invalidArgs("url is empty") }
        guard text.utf8.count <= maxInputLength else { throw .invalidArgs("url is too long") }
        guard text.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) })
        else { throw .invalidArgs("url contains whitespace") }
        guard var parts = URLComponents(string: text), let scheme = parts.scheme else {
            throw .invalidArgs("not a valid absolute url: \(text)")
        }
        let lowered = scheme.lowercased()
        guard lowered == "http" || lowered == "https" else {
            throw .deniedURL("only http and https urls can be opened")
        }
        guard let host = parts.host, !host.isEmpty else {
            throw .invalidArgs("url has no host")
        }
        parts.scheme = lowered
        parts.host = host.lowercased()
        guard let url = parts.url else { throw .invalidArgs("not a valid url: \(text)") }
        return url
    }

    /// The parent opens what the user names, anywhere under $HOME — a
    /// different scope from the specialist's workdir on purpose.
    public static func homePath(_ raw: String, home: URL) throws(ContractError) -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .invalidArgs("path is empty") }
        guard text.utf8.count <= maxInputLength else { throw .invalidArgs("path is too long") }
        let lexicalHome = home.standardizedFileURL.path
        // realpath(3) for both sides: Foundation's resolver strips
        // `/private`, realpath keeps it, and a home under /var would never
        // match itself.
        let canonicalHome = realpath(lexicalHome) ?? lexicalHome
        let expanded = expand(text, home: lexicalHome)

        // Barrier 1, lexical: `..` collapsed, no symlinks followed yet.
        let lexical = URL(fileURLWithPath: expanded).standardizedFileURL.path
        guard let rel = relative(lexical, to: lexicalHome) else {
            throw .deniedPath("path is outside the home folder")
        }
        try rejectHidden(rel)

        // Barrier 2, resolved: realpath semantics on the UN-collapsed path,
        // so `link/..` climbs from the link's target, not from the link.
        let (resolved, exists) = realpathOrNearest(expanded)
        guard let resolvedRel = relative(resolved, to: canonicalHome) else {
            throw .deniedPath("path resolves outside the home folder")
        }
        try rejectHidden(resolvedRel)
        try rejectLaunchers(resolvedRel)
        guard exists else { throw .notFound("path does not exist: \(lexical)") }
        return URL(fileURLWithPath: resolved)
    }

    /// Case-insensitive name resolution for `open_app`, with the closest
    /// names when it misses so the model can correct itself ("Safari", not
    /// "Safari Technology Preview").
    public static func resolveApp(_ name: String, among known: [String]) -> Result<String, ContractError> {
        let wanted = name.lowercased()
        if let exact = known.first(where: { $0.lowercased() == wanted }) { return .success(exact) }
        let close = known.filter { candidate in
            let lower = candidate.lowercased()
            return lower.contains(wanted) || wanted.contains(lower)
                || commonPrefix(lower, wanted) >= 3
        }
        let shown = Array(unique(close).prefix(3))
        let hint = shown.isEmpty ? "" : " Did you mean: \(shown.joined(separator: ", "))?"
        return .failure(.notFound("no app named \(name).\(hint) Use list_apps."))
    }

    // MARK: - private

    private static func expand(_ text: String, home: String) -> String {
        if text == "~" { return home }
        if text.hasPrefix("~/") { return home + text.dropFirst(1) }
        if text.hasPrefix("/") { return text }
        return home + "/" + text
    }

    private static func relative(_ path: String, to base: String) -> [String]? {
        if path == base { return [] }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return path.dropFirst(prefix.count).split(separator: "/").map(String.init)
    }

    private static func rejectHidden(_ components: [String]) throws(ContractError) {
        if components.contains(where: { $0.hasPrefix(".") }) {
            throw .deniedPath("hidden path components are not allowed")
        }
    }

    /// Every component, not only the last: a document INSIDE `Foo.app` is
    /// still a way to make LaunchServices touch the bundle.
    private static func rejectLaunchers(_ components: [String]) throws(ContractError) {
        for component in components {
            let ext = (component as NSString).pathExtension.lowercased()
            if launcherExtensions.contains(ext) {
                throw .deniedPath(
                    "apps, scripts and shortcuts cannot be opened this way; "
                    + "only documents and folders (use open_app for an app)")
            }
        }
    }

    /// realpath(3) of the path if it exists; otherwise of its nearest
    /// existing ancestor with the missing tail appended, so a missing file
    /// under a valid folder can be told apart from a denied one.
    private static func realpathOrNearest(_ path: String) -> (String, exists: Bool) {
        if let real = realpath(path) { return (real, true) }
        var tail: [String] = []
        var cursor = path
        while cursor != "/" {
            let url = URL(fileURLWithPath: cursor)
            tail.insert(url.lastPathComponent, at: 0)
            cursor = url.deletingLastPathComponent().path
            if let real = realpath(cursor) {
                return (([real] + tail).joined(separator: "/"), false)
            }
        }
        return (path, false)
    }

    private static func realpath(_ path: String) -> String? {
        guard let cString = Foundation.realpath(path, nil) else { return nil }
        defer { free(cString) }
        return String(cString: cString)
    }

    private static func isControl(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func commonPrefix(_ a: String, _ b: String) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }
}

/// Wave 10c 3D. The parent's hands ask no permission (10b) with one
/// exception: `open_url` for a host the user never named. A window title or
/// a clipboard can put a URL in front of the model (10a's security finding);
/// the user's own words are the only thing that lets it through unasked.
public enum ParentToolGate: Sendable {
    public static func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard call.name == ParentTool.openURL.rawValue,
              let raw = ToolArguments.parse(call.arguments)?["url"] as? String
        else { return nil }
        let url: URL
        do {
            url = try ParentToolPolicy.httpURL(raw)
        } catch {
            // The policy refuses it on its own; nothing to ask about.
            return nil
        }
        guard let host = url.host, !saidIt(url, host: host, said: said) else { return nil }
        return ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name,
            summary: "open \(host)", inputJSON: call.arguments)
    }

    /// The whole URL, the host without `www.`, or — for `brand.tld` and
    /// `brand.co.uk` only — the brand as a word. With a subdomain the whole
    /// host has to be said: without a public-suffix list, `attacker.github.io`
    /// would otherwise ride on the word "github" (security review
    /// 2026-09-05). A match inside a negated clause ("no abras …") is not
    /// consent.
    static func saidIt(_ url: URL, host: String, said: String) -> Bool {
        let words = said.lowercased()
        let lowered = host.lowercased()
        let bare = lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
        var candidates = [url.absoluteString.lowercased(), bare]
        let labels = bare.split(separator: ".").map(String.init)
        if labels.count == 2 {
            candidates.append(labels[0])
        } else if labels.count == 3,
                  ["co", "com", "org", "net", "gov", "edu", "ac"].contains(labels[1]) {
            candidates.append(labels[0])
        }
        for candidate in candidates where candidate.count >= 3 {
            let pattern = "(?<![a-z0-9.-])" + NSRegularExpression.escapedPattern(for: candidate)
                + "(?![a-z0-9]|\\.)"
            guard let range = words.range(of: pattern, options: .regularExpression) else { continue }
            if !negated(words, before: range.lowerBound) { return true }
        }
        return false
    }

    private static let negations: Set<String> = [
        "no", "not", "don't", "dont", "never", "nunca", "ni", "tampoco", "jamás", "jamas", "sin",
    ]

    /// A negation word in the same clause (back to the last `,;?!` or a
    /// sentence-ending ". " — a bare dot or colon belongs to the URL).
    private static func negated(_ words: String, before index: String.Index) -> Bool {
        let head = String(words[..<index]).replacingOccurrences(of: ". ", with: "\u{1}")
        let clause = head.split(whereSeparator: { ",;?!\u{1}".contains($0) }).last.map(String.init) ?? ""
        return clause.split(whereSeparator: { $0.isWhitespace })
            .contains { negations.contains(String($0)) }
    }
}
