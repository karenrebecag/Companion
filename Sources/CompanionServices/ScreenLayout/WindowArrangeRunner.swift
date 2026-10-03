import CompanionCore
import Foundation

/// `arrange_windows` for the conversation, composed next to the parent's
/// runner. Reading the screen and planning run unasked; moving windows runs
/// only on the yes the sheet gave for that exact call, the way the hands
/// act in a terminal. The undo snapshot is this runner's, never the model's.
package struct WindowArrangeRunner: ParentToolExecuting, Sendable {
    private let engine: WindowArrangeEngine
    private let undo: ArrangeUndoStore
    let tickets = ApprovalTickets()

    package init(arranging: any WindowArranging, undo: ArrangeUndoStore = ArrangeUndoStore()) {
        self.undo = undo
        self.engine = WindowArrangeEngine(arranging: arranging, undo: undo)
    }

    package func specs(_ language: AppLanguage) -> [ToolSpec] {
        [WindowArrangeTool.spec(language)]
    }

    package func handles(_ name: String) -> Bool { name == WindowArrangeTool.name }

    package func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard handles(call.name), let arguments = ToolArguments.parse(call.arguments),
              case .success(let parsed) = ArrangeWindowsCall.parse(arguments),
              let summary = WindowArrangeTool.approvalSummary(call.arguments)
        else { return nil }
        // Nothing to undo answers without a sheet; `execute` says so.
        if case .undo = parsed, !undo.hasSnapshot { return nil }
        let request = ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name, summary: summary, inputJSON: call.arguments)
        tickets.park(Self.ticket(call.arguments), id: request.requestId)
        return request
    }

    package func granted(_ request: ApprovalRequest) {
        tickets.grant(id: request.requestId)
    }

    package func withdraw(_ call: ToolCallRef) {
        tickets.revoke(name: call.name, arguments: call.arguments)
    }

    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        guard handles(name) else { return .failed(.notFound("unknown tool: \(name)")) }
        guard let arguments = ToolArguments.parse(argumentsJSON) else {
            return .failed(.invalidArgs(
                "could not parse arguments (\(argumentsJSON.count) chars); send one JSON object"), tool: name)
        }
        let call: ArrangeWindowsCall
        switch ArrangeWindowsCall.parse(arguments) {
        case .success(let parsed): call = parsed
        case .failure(let error): return .failed(error, tool: name)
        }
        if case .undo = call, !undo.hasSnapshot {
            return .failed(WindowArrangement.nothingToUndo, tool: name)
        }
        if call.needsApproval, !tickets.redeem(Self.ticket(argumentsJSON)) {
            Log.app("windows: \(name) refused, no approval for this call")
            return .failed(ContractError(
                code: "approval_required", message: "moving windows needs the user's yes on the sheet first"),
                tool: name)
        }
        switch await engine.run(call) {
        case .success(let report):
            return ParentToolOutcome(ok: true, output: report, target: WindowArrangeTool.target(call), tool: name)
        case .failure(let error):
            Log.app("windows: \(name) failed code=\(error.code)")
            return .failed(error, target: WindowArrangeTool.target(call), tool: name)
        }
    }

    /// The pid is meaningless here: the sheet approves one call's words.
    private static func ticket(_ arguments: String) -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(name: WindowArrangeTool.name, arguments: arguments, pid: 0)
    }
}
