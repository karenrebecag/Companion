import CryptoKit
import Foundation

/// The page the isolated web view loads (16m-5b), as data: what it runs,
/// what it may do, and where it may go. Pure, so the security posture is
/// pinned by tests instead of by reading a WKWebView setup.
public enum DiagramPage {
    /// Pinned in Sources/CompanionServices/Diagram/VENDOR.md too; a test
    /// fails if the file, the note and these two disagree.
    public static let mermaidVersion = "11.17.2"
    public static let mermaidSHA256 = "581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8"

    /// A diagram that has not drawn by now is text. Parsing 3.6 MB of script
    /// and laying out a big graph is a second or two; this only catches a hang.
    // HACK: not measured on the slowest supported Mac. Move it when a real
    // diagram is cut off by it.
    public static let renderTimeout: Duration = .seconds(10)

    /// The most a diagram may be tall before it is turned into a picture.
    /// A PDF of an absurd SVG costs memory the popup (480 tall) never shows.
    // HACK: unmeasured; a legitimate 100-step sequence diagram is ~3000.
    public static let maxImageHeight = 8000.0

    public static func acceptsHeight(_ height: Double) -> Bool {
        height.isFinite && height > 0 && height <= maxImageHeight
    }

    /// The only call into the page. The text is the `source` ARGUMENT
    /// (`callAsyncJavaScript`), never spliced into script.
    public static let renderCall = "return await window.renderDiagram(source)"

    /// Every Mermaid setting: values of Incredible's own `initialize`
    /// (docs/research/incredible-isla-componentes.md), plus one of ours,
    /// `suppressErrorRendering`, so a bad diagram throws instead of drawing
    /// Mermaid's error graphic into the page.
    public static var configJSON: String {
        let ink = "rgba(255, 255, 255, "
        let accents = ["#4a9cff", "#8b80ff", "#4cc2b4", "#f0a93b", "#f06b9b", "#56c596", "#c08bff", "#ffd166"]
        var theme: [String: Any] = [
            "darkMode": true,
            "background": "transparent",
            "fontFamily": fontFamily,
            "fontSize": "13px",
            "primaryColor": "#1e1e26",
            "primaryBorderColor": ink + "0.18)",
            "primaryTextColor": ink + "0.94)",
            "secondaryColor": "#191920",
            "secondaryBorderColor": ink + "0.12)",
            "tertiaryColor": "#15151b",
            "tertiaryBorderColor": ink + "0.1)",
            "lineColor": ink + "0.32)",
            "textColor": ink + "0.82)",
            "edgeLabelBackground": "#14141a",
            "clusterBkg": ink + "0.03)",
            "clusterBorder": ink + "0.1)",
            "noteBkgColor": "#23232c",
            "noteTextColor": ink + "0.9)",
            "noteBorderColor": ink + "0.14)",
            "primaryColorAccent": "#4a9cff",
            "pieStrokeColor": "#14141a",
            "pieStrokeWidth": "2px",
            "pieTitleTextColor": ink + "0.94)",
            "pieSectionTextColor": ink + "0.96)",
        ]
        for (index, color) in accents.enumerated() { theme["pie\(index + 1)"] = color }
        let config: [String: Any] = [
            "startOnLoad": false,
            "securityLevel": "strict",
            "theme": "base",
            "fontFamily": fontFamily,
            "suppressErrorRendering": true,
            "flowchart": ["curve": "basis", "padding": 14, "useMaxWidth": true] as [String: Any],
            "sequence": ["useMaxWidth": true, "mirrorActors": false] as [String: Any],
            "themeVariables": theme,
        ]
        return json(config)
    }

    private static let fontFamily = "-apple-system, BlinkMacSystemFont, \"Segoe UI\", system-ui, sans-serif"

    private static func json(_ object: [String: Any]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        } catch {
            // Unreachable for the literals above; an empty config would run
            // Mermaid at its defaults (loose security), so the page refuses.
            return "null"
        }
    }

    /// Runs after the vendored script. `mermaid.parse` first so a syntax
    /// error is a rejection, then the SVG lands in `#out` (already sanitized
    /// by `securityLevel: strict`) and only its height leaves the page.
    public static var bootstrapScript: String {
        """
        (function () {
          "use strict";
          if (\(configJSON) === null) { return; }
          mermaid.initialize(\(configJSON));
          window.renderDiagram = async function (source) {
            await mermaid.parse(source);
            const rendered = await mermaid.render("diagram", source);
            const out = document.getElementById("out");
            out.innerHTML = rendered.svg;
            return { height: Math.ceil(out.getBoundingClientRect().height) };
          };
        })();
        """
    }

    /// What the page paints behind the diagram. `createPDF` lays the page on
    /// white whatever its CSS says, and the theme's ink is light, so the page
    /// paints the popup container's own fill (5 % white over rgb(14,14,16))
    /// and the picture disappears into it. A test ties it to the UI values.
    public static let surface = "rgb(26, 26, 28)"

    /// Every remote load closed. `script-src` lists the two inline scripts
    /// by hash: an attribute handler or a script the model smuggles into a
    /// label matches neither and never runs.
    public static func contentSecurityPolicy(scriptHashes: [String]) -> String {
        let scripts = scriptHashes.map { "'\($0)'" }.joined(separator: " ")
        let closed = ["connect-src", "img-src", "font-src", "media-src", "object-src", "frame-src", "worker-src", "form-action", "base-uri"]
        return (["default-src 'none'", "script-src \(scripts)", "style-src 'unsafe-inline'"]
            + closed.map { "\($0) 'none'" }).joined(separator: "; ")
    }

    /// A CSP script hash: `sha256-` and the base64 of the script's UTF-8.
    public static func cspHash(_ script: String) -> String {
        "sha256-" + Data(SHA256.hash(data: Data(script.utf8))).base64EncodedString()
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The whole page. It holds no diagram text: that arrives as an argument.
    public static func html(vendorScript: String) -> String {
        let policy = contentSecurityPolicy(scriptHashes: [cspHash(vendorScript), cspHash(bootstrapScript)])
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">\
        <meta http-equiv="Content-Security-Policy" content="\(policy)">\
        <style>html,body{margin:0;padding:0;background:\(surface)}\
        #out{text-align:center}#out svg{max-width:100%;height:auto}</style></head>\
        <body><div id="out"></div><script>\(vendorScript)</script><script>\(bootstrapScript)</script></body></html>
        """
    }

    /// `loadHTMLString(_, baseURL: nil)` starts at about:blank; nothing else
    /// is a place this page may go (no link, no redirect, no form).
    public static func allowsNavigation(to url: URL?) -> Bool {
        url?.absoluteString == "about:blank"
    }

    /// WebKit content-blocker rule: any URL with a scheme and `//` (http,
    /// https, ws, wss, ftp, file, custom) is blocked. The page's own
    /// about:blank has none. Defense in depth behind the CSP.
    public static let blockNetworkRules = """
    [{"trigger":{"url-filter":"^[a-z][a-z0-9+.-]*://"},"action":{"type":"block"}}]
    """
}
