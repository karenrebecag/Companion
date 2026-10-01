import CompanionCore
import Foundation

/// The parent's gate (Wave 10c 3D `open_url`, Wave 15g Return in a
/// terminal) for the voice runtimes: asks through
/// the same actor the sheet resolves, and reports the request on the seam
/// that shows the sheet. Nil from `check` means go ahead; otherwise it is
/// the denial to answer the model with. No provider means fail closed.
///
/// Package-level since Wave 17: `BridgeSession`'s package init takes one across the
/// targets' package API surface (a package actor cannot have an internal
/// parameter type). The approval flow itself stays exactly what it was —
/// only the type's visibility changed.
package struct ParentToolGuard: Sendable {
    var approvals: (any ApprovalsProvider)?
    var onRequest: (@Sendable (ApprovalRequest) -> Void)?
    var onRemembered: (@Sendable (String, Bool) async -> Void)?
    var onSettled: (@Sendable (ApprovalRequest, SheetAnswer) -> Void)?

    package init(
        approvals: (any ApprovalsProvider)? = nil,
        onRequest: (@Sendable (ApprovalRequest) -> Void)? = nil,
        onRemembered: (@Sendable (String, Bool) async -> Void)? = nil,
        onSettled: (@Sendable (ApprovalRequest, SheetAnswer) -> Void)? = nil
    ) {
        self.approvals = approvals
        self.onRequest = onRequest
        self.onRemembered = onRemembered
        self.onSettled = onSettled
    }

    /// How a sheet ended. Only `denied` is the user refusing: a deadline is
    /// silence, and callers that count refusals must tell them apart.
    package enum SheetAnswer: Sendable, Equatable {
        case approved, denied, timedOut
        /// No sheet was shown: the bridge's sheets-per-window limit is spent.
        case refused
        /// The caller was cut while the sheet waited. Not the user refusing,
        /// so the bridge's cool-down must not count it.
        case abandoned
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
        // A "no" the user asked to remember outranks the shortcut: the same
        // write must not go through just because the cells are still empty.
        if let tools, await tools.actsWithoutSheet(call), await approvals?.remembered(request) != false {
            return Verdict(denial: nil, answer: nil)
        }
        let target = ParentTool.target(of: call)
        let denied = ParentToolOutcome.failed(
            .deniedByUser(language), target: target, tool: call.name)
        let sheet = await answer(request, parked: parked)
        // The sheet's wait is where the user can cut the caller: a yes that
        // lands after that answers a turn nobody is in any more, so it grants
        // nothing and leaves no ticket behind (approval-after-cut, D1).
        if Task.isCancelled {
            onSettled?(request, .abandoned)
            let cut = ParentToolOutcome.failed(.interrupted, target: target, tool: call.name)
            return Verdict(denial: cut, answer: .abandoned)
        }
        onSettled?(request, sheet)
        if sheet == .approved { tools?.granted(request) }
        return Verdict(denial: sheet == .approved ? nil : denied, answer: sheet)
    }

    /// The remembered/onRequest/request dance on its own, without a
    /// `ParentToolOutcome` to build: the bridge's session-open sheet
    /// ("wants to use your hands", spec §9-5) has no tool call behind it,
    /// just this `ApprovalRequest`.
    func ask(_ request: ApprovalRequest) async -> Bool {
        await answer(request, parked: nil) == .approved
    }

    /// The one point every sheet-backed decision without a tool call behind
    /// it goes through (16q-1: the realtime MCP request too), returning the
    /// whole response so whatever judges a request later has a single place
    /// to stand. Same road as `answer`: nothing here decides on its own.
    func decide(_ request: ApprovalRequest) async -> ApprovalResponse {
        let sheet = await answer(request, parked: nil)
        return ApprovalResponse(
            requestId: request.requestId, approved: sheet == .approved,
            timedOut: sheet == .timedOut)
    }

    /// `parked` runs right before the sheet is shown, so a caller that must
    /// withdraw it later already knows which one it is; returning false
    /// vetoes the sheet.
    func answer(
        _ request: ApprovalRequest, parked: (@Sendable (ApprovalRequest) -> Bool)?
    ) async -> SheetAnswer {
        guard let approvals else { return .denied }
        // Defense in depth over `ApprovalKey.from`: a provider with another
        // memory must still never answer an MCP request without its sheet.
        if !request.isMCP, let decision = await approvals.remembered(request) {
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
    /// False when nothing was parked under that id: a caller that reports
    /// the refusal as applied must know it was not.
    @discardableResult
    func withdraw(_ request: ApprovalRequest) async -> Bool {
        await approvals?.resolve(requestId: request.requestId, approved: false) ?? false
    }
}
