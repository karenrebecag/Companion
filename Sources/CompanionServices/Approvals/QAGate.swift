import CompanionCore
import Foundation

/// What QA mode decided for one action that would have opened a sheet.
package enum QAVerdict: Sendable, Equatable {
    /// QA is off, or the action keeps its sheet (the session grant): the
    /// caller asks the way it always has.
    case notInQA
    case act
    case granted
    case refused(code: String)
    case unavailable(code: String)
    /// Another owner check is already on screen. Not a no from the owner.
    case busy
}

/// Puente QA D5: in QA mode nothing opens a sheet. Safe and confirmable
/// actions run; critical ones need the owner's own check. Unwired in this
/// PR: no caller consults it yet.
package actor QAGate {
    package typealias Classify = @Sendable (_ toolName: String, _ arguments: String, _ said: String) -> ActionBand

    private let enabled: @Sendable () -> Bool
    private let owner: (any OwnerVerifying)?
    private let classify: Classify
    private let disableQA: @Sendable () -> Void
    private let language: @Sendable () -> AppLanguage
    private var verifying = false

    /// The default classifier knows no facts, which raises the band: an
    /// action whose target nobody looked at is critical, not free.
    package init(
        enabled: @escaping @Sendable () -> Bool,
        owner: (any OwnerVerifying)?,
        disableQA: @escaping @Sendable () -> Void,
        language: @escaping @Sendable () -> AppLanguage,
        classify: @escaping Classify = { name, arguments, _ in
            ActionBand.classify(
                toolName: name, arguments: ToolArguments.parse(arguments) ?? [:],
                facts: ActionFacts()
            )
        }
    ) {
        self.enabled = enabled
        self.owner = owner
        self.disableQA = disableQA
        self.language = language
        self.classify = classify
    }

    package func decide(_ request: ApprovalRequest, call: ToolCallRef, said: String) async -> QAVerdict {
        guard enabled() else { return .notInQA }
        let band = classify(call.name, call.arguments, said)
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
        defer { verifying = false }
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
