import CompanionCore
import Foundation

/// `remember` for the conversation, composed next to the parent's runner.
/// A fact in the user's own words this turn is saved without a sheet: one
/// line in a folder she can open, forgotten from Settings › Memoria. Any
/// other fact asks, because every later prompt reads it back as hers and a
/// page or a mail read this turn could be the one dictating it (QA
/// 2026-10-19: a web read does not taint the turn, so the taint signal let
/// it through). Local only: the bridge never lends it, or an outside agent
/// could plant notes that every later conversation reads as facts about her.
package struct MemoryToolRunner: ParentToolExecuting, Sendable {
    private let notes: any MemoryNoting

    package init(notes: any MemoryNoting) {
        self.notes = notes
    }

    package func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard handles(call.name) else { return nil }
        let fact = ToolArguments.parse(call.arguments)?["fact"] as? String ?? ""
        guard !HandsWords.said(fact, in: said) else { return nil }
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
