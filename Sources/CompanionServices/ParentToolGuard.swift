import CompanionCore
import Foundation

/// The parent's gate (Wave 10c 3D `open_url`, Wave 15g Return in a
/// terminal) for the voice runtimes: asks through
/// the same actor the sheet resolves, and reports the request on the seam
/// that shows the sheet. Nil from `check` means go ahead; otherwise it is
/// the denial to answer the model with. No provider means fail closed.
///
/// Public since Wave 17: `BridgeSession`'s public init takes one across the
/// module's own public API surface (a public actor cannot have an internal
/// parameter type). The approval flow itself stays exactly what it was —
/// only the type's visibility changed.
public struct ParentToolGuard: Sendable {
    var approvals: (any ApprovalsProvider)?
    var onRequest: (@Sendable (ApprovalRequest) -> Void)?
    var onRemembered: (@Sendable (String, Bool) async -> Void)?

    public init(
        approvals: (any ApprovalsProvider)? = nil,
        onRequest: (@Sendable (ApprovalRequest) -> Void)? = nil,
        onRemembered: (@Sendable (String, Bool) async -> Void)? = nil
    ) {
        self.approvals = approvals
        self.onRequest = onRequest
        self.onRemembered = onRemembered
    }

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
        let approved = await ask(request)
        if approved { tools?.granted(request) }
        return approved ? nil : denied
    }

    /// The remembered/onRequest/request dance on its own, without a
    /// `ParentToolOutcome` to build: the bridge's session-open sheet
    /// ("wants to use your hands", spec §9-5) has no tool call behind it,
    /// just this `ApprovalRequest`.
    func ask(_ request: ApprovalRequest) async -> Bool {
        await decide(request).approved
    }

    /// The one point every sheet-backed decision goes through (16q-1: the
    /// realtime MCP request too), returning the whole response so whatever
    /// judges a request later has a single place to stand.
    func decide(_ request: ApprovalRequest) async -> ApprovalResponse {
        guard let approvals else {
            return ApprovalResponse(requestId: request.requestId, approved: false)
        }
        if let decision = await approvals.remembered(request) {
            await onRemembered?(request.toolName, decision)
            return ApprovalResponse(requestId: request.requestId, approved: decision)
        }
        onRequest?(request)
        return await approvals.request(request)
    }

    /// "Stop hands" (spec §3 "Corte"): resolves a sheet the caller is still
    /// parked on, as a denial — without the caller reaching into
    /// `approvals` itself, which stays private to this struct.
    func withdraw(_ request: ApprovalRequest) async {
        _ = await approvals?.resolve(requestId: request.requestId, approved: false)
    }
}
