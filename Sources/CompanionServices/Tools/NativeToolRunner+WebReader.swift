import CompanionCore
import Foundation

extension NativeToolRunner {
    /// Reads one to three pages in full. The URLs leave the Mac for Exa, the
    /// same egress as a web_search query, so the band and the taint rules
    /// match web_search rather than web_fetch's.
    func runReadURL(arguments: [String: Any]) async -> ToolResult {
        guard let raw = arguments["urls"] as? String else {
            return ToolResult(ok: false, output: "Missing urls argument")
        }
        let tokens = ParentToolGate.addressTokens(raw)
        guard !tokens.isEmpty else {
            return ToolResult(ok: false, output: "Missing urls argument")
        }
        guard tokens.count <= ExaWebReader.maxURLs else {
            return ToolResult(
                ok: false, output: "read_url takes one to \(ExaWebReader.maxURLs) URLs")
        }
        let urls = tokens.compactMap { URL(string: $0) }.filter(EndpointPolicy.isAcceptable)
        guard urls.count == tokens.count else {
            let bad = tokens.first { token in
                URL(string: token).map { !EndpointPolicy.isAcceptable($0) } ?? true
            } ?? ""
            return ToolResult(ok: false, output: "Not a usable URL: \(bad)")
        }
        guard let webReader, webReader.isConfigured else {
            // Reachable only if something called the tool without asking
            // `availableTools` first, as with web_search.
            return ToolResult(ok: false, output: "Reading pages is not configured")
        }
        let fresh = arguments["fresh"] as? Bool ?? false
        do {
            let pages = try await webReader.read(urls, fresh: fresh)
            guard !pages.isEmpty else {
                return ToolResult(ok: false, output: "No page text for: \(tokens.joined(separator: " "))")
            }
            let blocks = pages.map { page in
                "## \(WebText.clean(page.title)) — \(page.url)\n\(WebText.clean(page.text))"
            }
            return ToolResult(
                ok: true, output: ([WebText.framing] + blocks).joined(separator: "\n\n"))
        } catch {
            return ToolResult(ok: false, output: "Reading the page failed: \(error)")
        }
    }
}
