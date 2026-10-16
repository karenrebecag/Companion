import CompanionCore
import Foundation

/// `remember` for the conversation, composed next to the parent's runner.
/// It asks no sheet: the user said it out loud, the write is one line in a
/// folder she can open, and Settings › Memoria forgets it. Local only: the
/// bridge never lends it, or an outside agent could plant notes that every
/// later conversation reads as facts about her.
package struct MemoryToolRunner: ParentToolExecuting, Sendable {
    private let notes: any MemoryNoting

    package init(notes: any MemoryNoting) {
        self.notes = notes
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
