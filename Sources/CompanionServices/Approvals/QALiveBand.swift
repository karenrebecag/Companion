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
        let arguments = ToolArguments.parse(call.arguments) ?? [:]
        var facts = ActionFacts()
        switch ParentTool(rawValue: call.name) {
        case .click, .menu:
            facts.destructiveTarget = true
        case .typeText, .pressKey:
            facts.inTerminal = terminal(in: request)
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
