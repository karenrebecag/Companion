import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// approval-after-cut (D1-C, D2-C): a sheet parked inside a turn the user has
// since cut must not let a later yes act for that turn. The fake parks until
// the test answers and ignores cancellation, which is what makes the click
// that beats the real actor's cancel handler reproducible here.

private let parked = ApprovalRequest(
    requestId: "r1", toolName: "open_url", summary: "open example.com", inputJSON: "{}")
private let openCall = ToolCallRef(
    id: "c1", name: "open_url", arguments: #"{"url":"https://example.com"}"#)

private func sheetTools() -> FakeParentTools {
    let tools = FakeParentTools(handledNames: ["open_url"])
    tools.setScriptedApproval(parked)
    return tools
}

private final class Settled: @unchecked Sendable {
    private let lock = NSLock()
    private var _answers: [(String, ParentToolGuard.SheetAnswer)] = []
    var answers: [(String, ParentToolGuard.SheetAnswer)] { lock.withLock { _answers } }
    func record(_ request: ApprovalRequest, _ answer: ParentToolGuard.SheetAnswer) {
        lock.withLock { _answers.append((request.requestId, answer)) }
    }
}

@Suite struct ApprovalAfterCut {
    @Test @MainActor func aYesThatLandsAfterTheCallerWasCutGrantsNothing() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let settled = Settled()
        let gate = ParentToolGuard(approvals: approvals, onSettled: { settled.record($0, $1) })

        let waiting = Task {
            await gate.verdict(openCall, said: "", language: .en, tools: tools, parked: nil)
        }
        await pumpUntilAsync("the sheet is up") { !approvals.requests.isEmpty }
        waiting.cancel()
        _ = await approvals.resolve(requestId: "r1", approved: true)
        let verdict = await waiting.value

        #expect(verdict.answer == .abandoned)
        #expect(verdict.denial?.output.hasPrefix("cancelled") == true,
                "the model must hear an interruption, not a refusal: \(verdict.denial?.output ?? "nil")")
        #expect(tools.grantedCalls.isEmpty, "a cut turn left a spendable ticket")
        #expect(settled.answers.map(\.0) == ["r1"])
        #expect(settled.answers.first?.1 == .abandoned)
    }

    @Test @MainActor func aYesForALiveCallerStillGoesThroughAndSettlesTheCard() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let settled = Settled()
        let gate = ParentToolGuard(approvals: approvals, onSettled: { settled.record($0, $1) })

        let waiting = Task {
            await gate.verdict(openCall, said: "", language: .en, tools: tools, parked: nil)
        }
        await pumpUntilAsync("the sheet is up") { !approvals.requests.isEmpty }
        _ = await approvals.resolve(requestId: "r1", approved: true)
        let verdict = await waiting.value

        #expect(verdict.answer == .approved)
        #expect(verdict.denial == nil)
        #expect(tools.grantedCalls.map(\.requestId) == ["r1"])
        #expect(settled.answers.first?.1 == .approved)
    }

    // The checklist's RED: the turn parks on the sheet, the press cuts it,
    // the yes lands afterwards, and nothing runs.
    @Test @MainActor func aClassicTurnCutWhileItsSheetWaitsNeverActsOnTheLateYes() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let chat = ScriptedChat()
        chat.rounds = [[.toolCalls([openCall])], [.text("Listo.")]]
        let transcriber = FakeTranscriber()
        transcriber.stoppedText = "abre la página"
        let runtime = ClassicRuntime(
            transcriber: transcriber, synthesizer: ScriptedSynth(), chat: chat, thread: ScriptedThread())
        runtime.parentGuard = ParentToolGuard(approvals: approvals)
        runtime.parentTools = tools

        let turn = Task { await runtime.submit(config: Config(language: .es)) { _ in } }
        await pumpUntilAsync("the sheet is up") { !approvals.requests.isEmpty }
        turn.cancel()
        _ = await approvals.resolve(requestId: "r1", approved: true)
        await turn.value

        #expect(tools.executeCalls.isEmpty, "the late yes acted for a turn the user had cut")
        #expect(chat.histories.count == 1, "the cut turn went back to the model")
    }

    // An unanswered call makes the next request to the model malformed, so
    // a cut round still answers every call, each as an interruption.
    @Test @MainActor func aCutRoundStillAnswersEveryCallAsInterrupted() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let runtime = ClassicRuntime(
            transcriber: FakeTranscriber(), synthesizer: ScriptedSynth(),
            chat: ScriptedChat(), thread: ScriptedThread())
        runtime.parentGuard = ParentToolGuard(approvals: approvals)
        let second = ToolCallRef(id: "c2", name: "open_url", arguments: #"{"url":"https://example.org"}"#)

        let round = Task {
            await runtime.actRound(
                [openCall, second], said: "", heard: "", using: tools, language: .en, unverified: [])
        }
        await pumpUntilAsync("the sheet is up") { !approvals.requests.isEmpty }
        round.cancel()
        _ = await approvals.resolve(requestId: "r1", approved: true)
        let acted = await round.value

        let answers = acted.turns.filter { $0.role == .tool }
        #expect(answers.map(\.toolCallID) == ["c1", "c2"], "one answer per call")
        #expect(answers.allSatisfy { $0.content == ContractError.interrupted.wire })
        #expect(tools.executeCalls.isEmpty)
    }
}
