import CompanionCore
import Foundation

/// The band QA mode judges a call by, from facts the runners already
/// established. A request only reaches the gate after its runner decided the
/// call needs a sheet, so the facts below are what that decision implies, read
/// from the request the runner built, never guessed from the tool name:
///
/// - `type_text` / `press_key`: the runner records whether the target is a
///   command app in the request (`terminal`).
/// - `click` / `menu`: the runner asks only for a destructive or unlabeled
///   control, so the target is destructive.
/// - files and workbooks: `actsWithoutSheet` already took the ones that only
///   add; what is left overwrites or lands outside the work zone, which the
///   default facts classify as critical.
///
/// Anything unclassified, and every MCP request, falls to critical.
package enum QALiveBand {
    package static func band(request: ApprovalRequest, call: ToolCallRef, said: String) -> ActionBand {
        guard !request.isMCP else { return .critical }
        // A connected app's tool reaches a third party. Its request only exists
        // because the runner found the action is not a read, and the group is not
        // reliable here, so it is critical and asks the owner (never `.confirm`).
        guard !call.name.hasPrefix(ApprovalCopy.appToolPrefix) else { return .critical }
        let arguments = ToolArguments.parse(call.arguments) ?? [:]
        var facts = ActionFacts()
        switch ParentTool(rawValue: call.name) {
        case .click, .menu:
            facts.destructiveTarget = true
        case .typeText, .pressKey:
            facts.inTerminal = terminal(in: request)
        case .openURL:
            // The runner marks a request it raised after a read outside the work folder.
            facts.tainted = (ToolArguments.parse(request.inputJSON)?["after_read"] as? Bool) == true
            if let raw = arguments["url"] as? String {
                do {
                    let url = try ParentToolPolicy.httpURL(raw)
                    if let host = url.host { facts.hostSaid = ParentToolGate.saidIt(url, host: host, said: said) }
                } catch {
                    // An address the policy refuses never reaches a sheet; critical stands.
                }
            }
        case nil where call.name == NativeTool.writeFile.rawValue || call.name == NativeTool.createDocument.rawValue:
            // The runner only asks about a file it did not already allow, so a
            // path that is free is a creation (confirm), not a replacement.
            if let path = arguments["path"] as? String, path.hasPrefix("/") || path.hasPrefix("~") {
                let expanded = (path as NSString).expandingTildeInPath
                facts.pathExists = NativeToolRunner.entryExists(expanded)
                facts.appOwned = NativeToolRunner.isAppOwned(
                    (expanded as NSString).resolvingSymlinksInPath,
                    home: FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path,
                    appRoot: nil)
            }
        default:
            break
        }
        return ActionBand.classify(toolName: call.name, arguments: arguments, facts: facts)
    }

    /// A request without the field is treated as a terminal: when the runner
    /// did not say, the safe reading is the one that asks the owner.
    private static func terminal(in request: ApprovalRequest) -> Bool {
        guard let fields = ToolArguments.parse(request.inputJSON),
              let flag = fields["terminal"] as? Bool else { return true }
        return flag
    }
}
