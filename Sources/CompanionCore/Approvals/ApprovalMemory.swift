import Foundation

/// `auto_approve_key` (corpus spec 16, FLOWS §7) in the grammar Claude Code
/// documents and companion already speaks through `can_use_tool`:
/// `Tool(pattern *)`, so a remembered rule reads the same on both sides.
package struct ApprovalKey: Hashable, Sendable, CustomStringConvertible {
    package var tool: String
    package var pattern: String

    package init(tool: String, pattern: String) {
        self.tool = tool
        self.pattern = pattern
    }

    package var description: String { "\(tool)(\(pattern))" }

    /// Tools that take a subcommand as their second word (`npm run`, `git
    /// status`): the subcommand is part of the pattern. For everything else
    /// only the command word counts, so `ls -la` and `ls /tmp` are one key.
    private static let subcommandTools: Set<String> = [
        "git", "npm", "npx", "yarn", "pnpm", "bun", "docker", "brew", "cargo",
        "swift", "pip", "pip3", "kubectl", "gh", "go", "make", "xcodebuild",
    ]

    /// `/bin/sh -c` runs the whole string: a key by first word would let a
    /// remembered `ls *` authorise `ls; curl … | sh` (security review
    /// 2026-09-05). A command with any shell metacharacter has no key — it
    /// is neither remembered nor answered from memory.
    package static func from(_ request: ApprovalRequest) -> ApprovalKey? {
        // A remote MCP server names its own tools: a key by name would let
        // its `run_shell` inherit, or plant, a rule the user set for the
        // local one. With no key it is never looked up nor stored.
        guard !request.isMCP else { return nil }
        let arguments = ToolArguments.parse(request.inputJSON) ?? [:]
        switch request.toolName {
        case NativeTool.runShell.rawValue:
            guard let command = arguments["command"] as? String,
                  command.unicodeScalars.allSatisfy({ !CommandClassifier.shellMetacharacters.contains($0) })
            else { return nil }
            let words = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let first = words.first else { return nil }
            // `file -C` writes a magic file. A remembered `file *` must not cover it.
            if first == "file", words.dropFirst().contains(where: { $0.hasPrefix("-") }) {
                return nil
            }
            if subcommandTools.contains(first), words.count > 1,
               words[1].range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil {
                return ApprovalKey(tool: request.toolName, pattern: "\(first) \(words[1]) *")
            }
            return ApprovalKey(tool: request.toolName, pattern: "\(first) *")
        case NativeTool.sheetWrite.rawValue:
            // Wave 20c D4: a remembered yes covers the identical write only:
            // the workbook and a hash of the cells are in the key, so it is
            // never a blank cheque over a range or a workbook.
            guard let range = (arguments["range"] as? String).flatMap(SheetRange.init(a1:)) else { return nil }
            // Without an app the target is whatever is in front when it runs,
            // which is not what the user approved.
            guard let app = (arguments["app"] as? String)?.lowercased(),
                  let workbook = SheetApproval.workbook(in: arguments),
                  case .success(let cells) = SheetValues.parse(any: arguments["values"], for: range)
            else { return nil }
            return ApprovalKey(
                tool: request.toolName,
                pattern: "\(app) \(range.a1) \(workbook) #\(SheetApproval.fingerprint(cells))")
        case NativeTool.createDocument.rawValue:
            // The file, not its folder: one yes must not cover every
            // deliverable a folder holds (20c D4, M6).
            guard let path = arguments["path"] as? String, !path.isEmpty, !path.hasSuffix("/") else { return nil }
            return ApprovalKey(tool: request.toolName, pattern: path)
        case NativeTool.writeFile.rawValue, NativeTool.editFile.rawValue:
            guard let path = arguments["path"] as? String, !path.isEmpty else { return nil }
            var directory = (path as NSString).deletingLastPathComponent
            if directory.isEmpty { directory = "." }
            return ApprovalKey(tool: request.toolName, pattern: directory + "/*")
        case ParentTool.openURL.rawValue:
            guard let raw = arguments["url"] as? String else { return nil }
            do {
                let url = try ParentToolPolicy.httpURL(raw)
                guard let host = url.host, let scheme = url.scheme else { return nil }
                // Scheme and port are part of the origin: a yes for
                // https://h must not open http://h or h on another port.
                let port = url.port ?? (scheme == "https" ? 443 : 80)
                return ApprovalKey(tool: request.toolName, pattern: "\(scheme)://\(host):\(port)")
            } catch {
                return nil
            }
        default:
            // Security review 2026-09-28 (HIGH): `bridge_session`
            // deliberately falls through to here. `client` is a name the
            // peer put on the wire, not an identity — any same-uid process
            // that read `bridge.token` could claim `client: "claude-code"`
            // and, if "remember" was ever ticked once, inherit the hands
            // with no sheet. One sheet per connection, every time.
            // A tool without a rule here is never remembered: `Tool(*)` for
            // a future risky tool would be blanket consent by omission.
            return nil
        }
    }
}

/// What the session remembers. Immutable, process-lifetime, never on disk
/// (Wave 10c 3B.2). A remembered denial outranks a later approval: Claude
/// Code evaluates `deny` before `allow`, and "no" said once must not be
/// talked over by a "yes" said later for the same key.
package struct ApprovalMemory: Sendable, Equatable {
    private var decisions: [ApprovalKey: Bool] = [:]

    package init() {}

    package func decision(for key: ApprovalKey) -> Bool? {
        decisions[key]
    }

    package func remembering(_ key: ApprovalKey, approved: Bool) -> ApprovalMemory {
        if decisions[key] == false { return self }
        var copy = self
        copy.decisions[key] = approved
        return copy
    }
}
