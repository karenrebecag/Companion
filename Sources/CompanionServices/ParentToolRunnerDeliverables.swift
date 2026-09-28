import CompanionCore
import Foundation

// Wave 20b D2: the parent runs create_document, sheet_read and sheet_write
// through the native runner, so both lanes share one implementation. A write
// runs only on a ticket the gate granted for that exact call: the native
// runner is told `approved: true` only after the ticket is spent.

extension ParentToolRunner {
    var deliverables: [NativeTool] {
        NativeTool.parentDeliverables.filter { tool in
            switch tool {
            case .createDocument: documents != nil
            case .sheetRead, .sheetWrite: sheets != nil
            default: false
            }
        }
    }

    func deliverableApproval(for call: ToolCallRef) -> ApprovalRequest? {
        guard let tool = NativeTool(rawValue: call.name), deliverables.contains(tool),
              tool.riskLevel == .requiresApproval else { return nil }
        // Refused in execute: nothing to approve.
        if tool == .sheetWrite, Self.unnamedApp(call.arguments) { return nil }
        let request = ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name,
            summary: "Tool requires user approval", inputJSON: call.arguments)
        deliverableTickets.park(Self.ticket(call.name, call.arguments), id: request.requestId)
        return request
    }

    func runDeliverable(
        _ tool: NativeTool, arguments: [String: Any], argumentsJSON: String
    ) async -> ParentToolOutcome {
        if tool == .sheetWrite, Self.unnamedApp(argumentsJSON) {
            return ParentToolOutcome(
                ok: false, output: "invalid_args: name the app (\"excel\" or \"numbers\") so the sheet "
                    + "shows the workbook it approves", tool: tool.rawValue)
        }
        let approved = tool.riskLevel != .requiresApproval
            || deliverableTickets.redeem(Self.ticket(tool.rawValue, argumentsJSON))
        let native = NativeToolRunner(
            workdir: workdir, places: nil, webSearch: nil, documents: documents, sheets: sheets)
        do {
            let result = try await native.execute(tool: tool.rawValue, arguments: arguments, approved: approved)
            return ParentToolOutcome(ok: result.ok, output: result.output, card: result.card, tool: tool.rawValue)
        } catch {
            Log.app("parent: \(tool.rawValue) failed")
            return ParentToolOutcome(ok: false, output: "\(tool.rawValue) failed", tool: tool.rawValue)
        }
    }

    /// Without an app the target is whatever is in front when the write
    /// runs, not what the user approved (security review 20b).
    private static func unnamedApp(_ argumentsJSON: String) -> Bool {
        let app = (ToolArguments.parse(argumentsJSON)?["app"] as? String)?.lowercased()
        return app.flatMap(SheetApp.init(rawValue:)) == nil
    }

    /// The pid is meaningless here: the sheet approves a call, not an app.
    private static func ticket(_ name: String, _ arguments: String) -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(name: name, arguments: arguments, pid: 0)
    }
}
