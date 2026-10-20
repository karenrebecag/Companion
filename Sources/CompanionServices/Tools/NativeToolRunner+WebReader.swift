import CompanionCore
import Foundation

extension NativeToolRunner {
    /// Reads one to three pages in full. Exa fetches each URL server-side, so
    /// the address is an egress like web_fetch's (ActionBand and the chat gate
    /// judge it the same way), not the web_search class, whose query goes to a
    /// fixed provider.
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
        // The same parse the chat gate judged (ParentToolGate.fetchURLs): a
        // refused address refuses the whole call before anything is contacted.
        guard let urls = ParentToolGate.fetchURLs(
            tool: NativeTool.readURL.rawValue, arguments: arguments)
        else {
            return ToolResult(ok: false, output: "Not a usable URL: \(tokens.joined(separator: " "))")
        }
        guard urls.allSatisfy(PageFetchPolicy.isAcceptable) else {
            return ToolResult(ok: false, output: "URL not acceptable by security policy")
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
            // Each page is fenced so its text cannot open a block of its own.
            let blocks = pages.map { WebText.fence($0) }
            return ToolResult(
                ok: true, output: ([WebText.framing] + blocks).joined(separator: "\n\n"))
        } catch {
            return ToolResult(ok: false, output: "Reading the page failed: \(error)")
        }
    }
}
