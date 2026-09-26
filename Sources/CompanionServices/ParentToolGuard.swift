import CompanionCore
import Foundation

/// The parent's gate (Wave 10c 3D `open_url`, Wave 15g Return in a
/// terminal) for the voice runtimes: asks through
/// the same actor the sheet resolves, and reports the request on the seam
/// that shows the sheet. Nil from `check` means go ahead; otherwise it is
/// the denial to answer the model with. No provider means fail closed.
struct ParentToolGuard: Sendable {
    var approvals: (any ApprovalsProvider)?
    var onRequest: (@Sendable (ApprovalRequest) -> Void)?
    var onRemembered: (@Sendable (String, Bool) async -> Void)?

    func check(
        _ call: ToolCallRef, said: String, language: AppLanguage,
        tools: (any ParentToolExecuting)? = nil
    ) async -> ParentToolOutcome? {
        let request = tools?.approval(for: call, said: said)
            ?? ParentToolGate.approval(for: call, said: said)
        guard let request else { return nil }
        let target = ParentTool.target(of: call)
        let denied = ParentToolOutcome.failed(
            .deniedByUser(language), target: target, tool: call.name)
        guard let approvals else { return denied }
        if let decision = await approvals.remembered(request) {
            await onRemembered?(call.name, decision)
            if decision { tools?.granted(request) }
            return decision ? nil : denied
        }
        onRequest?(request)
        guard await approvals.request(request).approved else { return denied }
        tools?.granted(request)
        return nil
    }
}
