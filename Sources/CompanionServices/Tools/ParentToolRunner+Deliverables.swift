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
            case .listFileHistory, .restoreFileVersion: versions != nil
            default: false
            }
        }
    }

    func deliverableApproval(for call: ToolCallRef) -> ApprovalRequest? {
        guard let tool = NativeTool(rawValue: call.name), deliverables.contains(tool),
              tool.riskLevel == .requiresApproval else { return nil }
        // Refused in execute: nothing to approve.
        if tool == .sheetWrite, Self.unnamedApp(call.arguments) { return nil }
        let shown = tool == .restoreFileVersion ? nativeRunner.restoreSheetJSON(call.arguments) : call.arguments
        let request = ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name,
            summary: "Tool requires user approval", inputJSON: shown)
        deliverableTickets.park(Self.ticket(call.name, call.arguments), id: request.requestId)
        return request
    }

    /// Only cells that were empty: the sheet exists to stop an overwrite, and
    /// the runner checks that itself. `runDeliverable` reads the range again
    /// before it writes, and without a sheet or a ticket a range that filled
    /// in between is refused.
    // HACK: the read and the write are two Apple Events, so a cell typed in
    // that gap is overwritten (the version kept before the write is the net). Upgrade
    // trigger: an "only if empty" flag on `SpreadsheetDriving.write`.
    package func actsWithoutSheet(_ call: ToolCallRef) async -> Bool {
        guard let arguments = ToolArguments.parse(call.arguments) else { return false }
        switch call.name {
        case NativeTool.createDocument.rawValue:
            // The sheet exists to stop a replacement; a name nobody holds yet has
            // nothing to stop. It stays a request until here so a remembered "no"
            // is checked by the same guards as every other write.
            return nativeRunner.fileBand(tool: call.name, arguments: arguments) == .act
        case NativeTool.sheetWrite.rawValue:
            guard !Self.unnamedApp(call.arguments) else { return false }
            return await nativeRunner.actionBand(tool: call.name, arguments: arguments) == .act
        default:
            return false
        }
    }

    var nativeRunner: NativeToolRunner {
        NativeToolRunner(workdir: workdir, places: nil, webSearch: nil, documents: documents, sheets: sheets,
                         versions: versions)
    }

    /// The sheet for a write names the workbook the runner sees in front, and
    /// the ticket is re-parked bound to it: a yes covers that workbook only.
    package func bound(_ request: ApprovalRequest) async -> ApprovalRequest {
        guard request.toolName == NativeTool.sheetWrite.rawValue else { return request }
        guard let sheets, let app = Self.sheetApp(request.inputJSON) else {
            var unbound = request
            unbound.inputJSON = SheetApproval.bind(request.inputJSON, workbook: nil)
            return unbound
        }
        var workbook: String?
        do {
            workbook = try await sheets.workbook(app)
        } catch {
            // HACK: an unresolvable workbook (unsaved file) still shows a sheet that
            // can never succeed. `bound` cannot refuse; give the seam (approval/bound)
            // a denial channel when that shows up in live use.
            Log.app("parent: workbook not resolved for approval")
        }
        if let workbook {
            deliverableTickets.park(Self.ticket(request.toolName, request.inputJSON, item: workbook),
                                    id: request.requestId)
        }
        var bound = request
        bound.inputJSON = SheetApproval.bind(request.inputJSON, workbook: workbook)
        return bound
    }

    func runDeliverable(
        _ tool: NativeTool, arguments: [String: Any], argumentsJSON: String
    ) async -> ParentToolOutcome {
        if tool == .sheetWrite, Self.unnamedApp(argumentsJSON) {
            return ParentToolOutcome(
                ok: false, output: "invalid_args: name the app (\"excel\" or \"numbers\") so the sheet "
                    + "shows the workbook it approves", tool: tool.rawValue)
        }
        var arguments = arguments
        var item = ""
        if tool == .sheetWrite, let sheets, let app = Self.sheetApp(argumentsJSON) {
            do {
                item = try await sheets.workbook(app)
            } catch {
                return ParentToolOutcome(
                    ok: false, output: NativeToolRunner.failure(error).output, tool: tool.rawValue)
            }
            // Only the workbook in front now is asked about: the yes that was
            // parked names the one the sheet showed, so a swap finds no ticket.
            arguments["workbook"] = item
        }
        let native = nativeRunner
        var acts = false
        if tool.riskLevel == .requiresApproval {
            acts = await native.actionBand(tool: tool.rawValue, arguments: arguments) == .act
        }
        let approved = tool.riskLevel != .requiresApproval || acts
            || deliverableTickets.redeem(Self.ticket(tool.rawValue, argumentsJSON, item: item))
        do {
            let result = try await native.execute(tool: tool.rawValue, arguments: arguments, approved: approved)
            if acts, result.ok, let receipt = await native.receipt(tool: tool.rawValue, arguments: arguments) {
                onAct?(receipt)
            }
            return ParentToolOutcome(ok: result.ok, output: result.output, card: result.card, tool: tool.rawValue)
        } catch {
            Log.app("parent: \(tool.rawValue) failed")
            return ParentToolOutcome(ok: false, output: "\(tool.rawValue) failed", tool: tool.rawValue)
        }
    }

    /// Without an app the target is whatever is in front when the write
    /// runs, not what the user approved (security review 20b).
    private static func unnamedApp(_ argumentsJSON: String) -> Bool {
        sheetApp(argumentsJSON) == nil
    }

    static func sheetApp(_ argumentsJSON: String) -> SheetApp? {
        (ToolArguments.parse(argumentsJSON)?["app"] as? String).map { $0.lowercased() }.flatMap(SheetApp.init(rawValue:))
    }

    /// The pid is meaningless here: the sheet approves a call, not an app.
    private static func ticket(_ name: String, _ arguments: String, item: String = "") -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(name: name, arguments: arguments, pid: 0, item: item)
    }
}
