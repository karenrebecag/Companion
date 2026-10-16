import CompanionCore
import Foundation

/// Puente QA D5: in QA mode nothing opens a sheet. Safe and confirmable
/// actions run; critical ones need the owner's own check. The chat's gate and
/// the bridge's `ParentToolGuard` consult the same instance.
package actor QAGate: QAGating {
    package typealias Classify = @Sendable (_ request: ApprovalRequest, _ call: ToolCallRef, _ said: String) -> ActionBand

    private let enabled: @Sendable () -> Bool
    private let owner: (any OwnerVerifying)?
    private let classify: Classify
    private let disableQA: @Sendable () -> Void
    private let language: @Sendable () -> AppLanguage
    private let ownerCheckChanged: @Sendable (_ open: Bool, _ tool: String) -> Void
    private var verifying = false

    /// `classify` has no default on purpose: one that guesses the facts
    /// lets hands act on a "Delete" button. The live gates pass `QALiveBand`;
    /// `QAApprovalPolicy.bandWithoutFacts` is for tests that have no runner.
    package init(
        enabled: @escaping @Sendable () -> Bool,
        owner: (any OwnerVerifying)?,
        disableQA: @escaping @Sendable () -> Void,
        language: @escaping @Sendable () -> AppLanguage,
        ownerCheckChanged: @escaping @Sendable (_ open: Bool, _ tool: String) -> Void = { _, _ in },
        classify: @escaping Classify
    ) {
        self.enabled = enabled
        self.owner = owner
        self.disableQA = disableQA
        self.language = language
        self.ownerCheckChanged = ownerCheckChanged
        self.classify = classify
    }

    package func canVerify() async -> Bool {
        guard let owner else { return false }
        return await owner.canVerify()
    }

    package func decide(_ request: ApprovalRequest, call: ToolCallRef, said: String) async -> QAVerdict {
        guard enabled() else { return .notInQA }
        // Either name can be the session grant: the band comes from one and
        // the sheet exception from the other, so a mismatch must not slip by.
        let session = BridgePolicy.sessionApprovalTool
        if call.name == session || request.toolName == session { return .notInQA }
        let band = classify(request, call, said)
        switch QAApprovalPolicy.decide(band: band, tool: request.toolName) {
        case .sheet:
            return .notInQA
        case .act:
            Log.app("qa gate: tool=\(request.toolName) band=\(band) act")
            return .act
        case .ownerCheck:
            return await ownerCheck(request.toolName)
        }
    }

    private func ownerCheck(_ tool: String) async -> QAVerdict {
        // Fail closed: with no port nobody can prove who is asking, and QA
        // mode no longer meets its own precondition.
        guard let owner else {
            Log.app("qa gate: tool=\(tool) band=critical no owner port")
            disableQA()
            return .unavailable(code: "owner_unavailable")
        }
        guard !verifying else { return .busy }
        verifying = true
        // The island and the waiting agent learn a dialog is on screen, so
        // the person is told to touch the sensor instead of staring at a stall.
        ownerCheckChanged(true, tool)
        defer {
            verifying = false
            ownerCheckChanged(false, tool)
        }
        let check = await owner.verify(reason: ApprovalCopy.ownerReason(language()))
        // A call cancelled while the dialog was up never acts, whatever the
        // system answered in the same instant.
        let outcome = Task.isCancelled
            ? QAApprovalPolicy.Outcome.refused(code: "owner_refused")
            : QAApprovalPolicy.outcome(for: check)
        Log.app("qa gate: tool=\(tool) band=critical \(outcome)")
        switch outcome {
        case .granted:
            return .granted
        case .refused(let code):
            return .refused(code: code)
        case .unavailable(let code):
            disableQA()
            return .unavailable(code: code)
        }
    }
}
