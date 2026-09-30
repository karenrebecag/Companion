import Foundation

public enum HostLaunch: Equatable, Sendable {
    case app
    case nativeHost(origin: String)
    case rejected
}

/// Wave 18. What the browser may hand back and what may be done with it.
/// The extension filters first; this filters again because the extension is
/// code running next to arbitrary web pages, not a trust boundary.
public enum BrowserPolicy {
    /// Derived from the public `key` in Extensions/browser/manifest.json;
    /// rotating that key means changing this id in the same commit.
    public static let pinnedExtensionID = "gaipfdnbliibnfchgcnamnjpfgkilnll"

    public static let pinnedOrigins: Set<String> = ["chrome-extension://\(pinnedExtensionID)/"]

    private static let originPrefix = "chrome-extension://"

    /// Chrome launches a native host as `path chrome-extension://<id>/` (a
    /// manifest cannot carry arguments), so the mode is read from argv[1].
    /// An extension origin that is not pinned is rejected, never treated as
    /// a normal launch: the app must not open its UI for a stranger's call.
    public static func launch(arguments: [String]) -> HostLaunch {
        guard arguments.count > 1 else { return .app }
        let first = arguments[1]
        // A bare `--native-host` is rejected rather than opening the full app:
        // whoever passes it is trying to reach host mode with a pipe on stdio,
        // and the UI must not start under that. Host mode has no test hook;
        // tests call BrowserHostRelay.run directly.
        if first == "--native-host" { return .rejected }
        guard first.hasPrefix(originPrefix) else { return .app }
        return pinnedOrigins.contains(first) ? .nativeHost(origin: first) : .rejected
    }

    // MARK: Sensitive fields

    private static let sensitiveTokens: Set<String> = ["one-time-code", "current-password", "new-password"]

    /// Keep identical to SENSITIVE_NAME in Extensions/browser/lib/page.js; the
    /// shared fixture tests on both sides pin the two together.
    private static let sensitiveNameWords: Set<String> = ["otp", "pin", "cvv", "cvc", "ssn", "password", "passwd"]

    /// A word bounded by `_`, `-` or the ends: "user_pin" yes, "spinner" no.
    private static func namesASecret(_ name: String) -> Bool {
        name.lowercased().split(omittingEmptySubsequences: false, whereSeparator: { $0 == "_" || $0 == "-" })
            .contains { sensitiveNameWords.contains(String($0)) }
    }

    public static func isSensitive(_ element: BrowserElement) -> Bool {
        if element.inputType?.lowercased() == "password" { return true }
        for name in [element.fieldName, element.fieldId] {
            if let name, namesASecret(name) { return true }
        }
        let tokens = (element.autocomplete ?? "").lowercased().split(whereSeparator: \.isWhitespace)
        return tokens.contains { $0.hasPrefix("cc-") || sensitiveTokens.contains(String($0)) }
    }

    private static func isHidden(_ element: BrowserElement) -> Bool {
        element.inputType?.lowercased() == "hidden"
    }

    /// Sensitive values are removed even if the extension sent them; the
    /// field itself stays listed so the model knows it is there and that it
    /// cannot type into it.
    public static func scrub(_ page: BrowserPage) -> BrowserPage {
        var clean = page
        clean.elements = page.elements.filter { !isHidden($0) }.map { element in
            guard isSensitive(element) else { return element }
            var stripped = element
            stripped.value = nil
            return stripped
        }
        return clean
    }
}
