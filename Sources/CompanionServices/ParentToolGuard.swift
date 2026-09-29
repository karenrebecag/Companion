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

    /// How a sheet ended. Only `denied` is the user refusing: a deadline is
    /// silence, and callers that count refusals must tell them apart.
    enum SheetAnswer: Sendable, Equatable {
        case approved, denied, timedOut
        /// No sheet was shown: the bridge's sheets-per-window limit is spent.
        case refused
    }

    /// `check`'s answer plus how the sheet ended, for callers that count
    /// refusals (the bridge's cool-down).
    struct Verdict: Sendable {
        let denial: ParentToolOutcome?
        let answer: SheetAnswer?
    }

    func check(
        _ call: ToolCallRef, said: String, language: AppLanguage,
        tools: (any ParentToolExecuting)? = nil
    ) async -> ParentToolOutcome? {
        await verdict(call, said: said, language: language, tools: tools, parked: nil).denial
    }

    func verdict(
        _ call: ToolCallRef, said: String, language: AppLanguage,
        tools: (any ParentToolExecuting)? = nil,
        parked: (@Sendable (ApprovalRequest) -> Bool)?
    ) async -> Verdict {
        let asked = tools?.approval(for: call, said: said)
            ?? ParentToolGate.approval(for: call, said: said)
        guard let asked else { return Verdict(denial: nil, answer: nil) }
        let request = await tools?.bound(asked) ?? asked
        let target = ParentTool.target(of: call)
        let denied = ParentToolOutcome.failed(
            .deniedByUser(language), target: target, tool: call.name)
        let answer = await answer(request, parked: parked)
        if answer == .approved { tools?.granted(request) }
        return Verdict(denial: answer == .approved ? nil : denied, answer: answer)
    }

    /// The remembered/onRequest/request dance on its own, without a
    /// `ParentToolOutcome` to build: the bridge's session-open sheet
    /// ("wants to use your hands", spec §9-5) has no tool call behind it,
    /// just this `ApprovalRequest`.
    func ask(_ request: ApprovalRequest) async -> Bool {
        await answer(request, parked: nil) == .approved
    }

    /// `parked` runs right before the sheet is shown, so a caller that must
    /// withdraw it later already knows which one it is; returning false
    /// vetoes the sheet.
    func answer(
        _ request: ApprovalRequest, parked: (@Sendable (ApprovalRequest) -> Bool)?
    ) async -> SheetAnswer {
        guard let approvals else { return .denied }
        if let decision = await approvals.remembered(request) {
            await onRemembered?(request.toolName, decision)
            return decision ? .approved : .denied
        }
        if let parked, !parked(request) { return .refused }
        onRequest?(request)
        let response = await approvals.request(request)
        if response.approved { return .approved }
        return response.timedOut ? .timedOut : .denied
    }

    /// "Stop hands" (spec §3 "Corte"): resolves a sheet the caller is still
    /// parked on, as a denial — without the caller reaching into
    /// `approvals` itself, which stays private to this struct.
    func withdraw(_ request: ApprovalRequest) async {
        _ = await approvals?.resolve(requestId: request.requestId, approved: false)
    }
}
