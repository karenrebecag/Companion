import CompanionCore
import Foundation

/// A real runner behind a seam that cuts the caller at one chosen point,
/// right after the runner has handed out a ticket. `granted` and
/// `approval(for:)` are synchronous, so no other thread can land a cut there
/// on cue: the seam does it itself (approval-ticket-on-cut, section 9).
package final class CuttingParentTools: ParentToolExecuting, @unchecked Sendable {
    package enum Point: Sendable {
        /// After a sheet's yes became a ticket.
        case granted
        /// After the runner issued a ticket for words the user said.
        case approval
    }

    package let inner: any ParentToolExecuting
    private let point: Point
    private let cut: @Sendable () -> Void

    package init(
        _ inner: any ParentToolExecuting, at point: Point,
        cut: @escaping @Sendable () -> Void = CuttingParentTools.cancelCurrentTask
    ) {
        self.inner = inner
        self.point = point
        self.cut = cut
    }

    /// The press, as the runtime sees it: the task running the call is
    /// cancelled.
    package static let cancelCurrentTask: @Sendable () -> Void = {
        withUnsafeCurrentTask { $0?.cancel() }
    }

    package func specs(_ language: AppLanguage) -> [ToolSpec] { inner.specs(language) }
    package func handles(_ name: String) -> Bool { inner.handles(name) }
    package func unavailability(for name: String) -> String? { inner.unavailability(for: name) }
    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        await inner.execute(name: name, argumentsJSON: argumentsJSON)
    }
    package func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        let request = inner.approval(for: call, said: said)
        if point == .approval { cut() }
        return request
    }
    package func bound(_ request: ApprovalRequest) async -> ApprovalRequest { await inner.bound(request) }
    package func actsWithoutSheet(_ call: ToolCallRef) async -> Bool { await inner.actsWithoutSheet(call) }
    package func granted(_ request: ApprovalRequest) {
        inner.granted(request)
        if point == .granted { cut() }
    }
    package func withdraw(_ call: ToolCallRef) { inner.withdraw(call) }
    package func beginTurn() { inner.beginTurn() }
    package func noteTurn(_ said: String) { inner.noteTurn(said) }
    package func noteChoiceTurn() { inner.noteChoiceTurn() }
}
