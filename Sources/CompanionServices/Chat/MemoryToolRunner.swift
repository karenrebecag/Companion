import CompanionCore
import Foundation

/// `remember` for the conversation, composed next to the parent's runner.
/// It asks no sheet in a clean turn: the user said it out loud, the write is
/// one line in a folder she can open, and Settings › Memoria forgets it. After
/// a read outside the work folder the words may be a page's, so it asks
/// (`ActionBand`). Local only: the
/// bridge never lends it, or an outside agent could plant notes that every
/// later conversation reads as facts about her.
package struct MemoryToolRunner: ParentToolExecuting, Sendable {
    private let notes: any MemoryNoting
    private let taint: TurnTaint

    /// `taint` is the one the parent's runner resets each turn; a private
    /// default would never see a page read and the sheet would never ask.
    package init(notes: any MemoryNoting, taint: TurnTaint = TurnTaint()) {
        self.notes = notes
        self.taint = taint
    }

    package func band(for call: ToolCallRef) async -> ActionBand {
        ActionBand.classify(toolName: call.name, arguments: [:], facts: ActionFacts(tainted: taint.isTainted))
    }

    package func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard handles(call.name), taint.isTainted else { return nil }
        return ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name,
            summary: "Tool requires user approval", inputJSON: call.arguments)
    }

    package func specs(_ language: AppLanguage) -> [ToolSpec] {
        [MemoryTool.spec(language)]
    }

    package func handles(_ name: String) -> Bool { name == MemoryTool.name }

    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        guard handles(name) else { return .failed(.notFound("unknown tool: \(name)")) }
        guard let arguments = ToolArguments.parse(argumentsJSON),
              let raw = arguments["fact"] as? String
        else { return .failed(.invalidArgs("send one JSON object with a fact"), tool: name) }
        switch MemoryTool.accepted(raw) {
        case .failure(let error):
            return .failed(error, tool: name)
        case .success(let fact):
            do {
                try notes.remember(fact)
            } catch {
                Log.app("memory: could not save a note (\(error))")
                return .failed(ContractError(code: "write_failed", message: "could not save it"), tool: name)
            }
            return ParentToolOutcome(ok: true, output: "saved", tool: name)
        }
    }
}
