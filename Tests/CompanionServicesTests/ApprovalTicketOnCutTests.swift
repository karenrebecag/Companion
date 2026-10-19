import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// approval-ticket-on-cut (Karen, 2026-10-01): a call dropped after the gate
// has handed out its ticket must take the ticket with it. Otherwise the
// fail-closed check `execute` runs for a path that skipped the gate finds a
// spendable ticket for up to 60 s. Every test spends the leftover through
// the real runner afterwards, outside the cut task.

/// What the model asks for in a terminal: typing that always needs a ticket.
private let typing = ToolCallRef(id: "c1", name: "type_text", arguments: #"{"text":"ls -la"}"#)

private func terminal() -> (FakeHands, ParentToolRunner) {
    let hands = FakeHands(field: FocusedField(app: "Terminal", pid: 7))
    return (hands, handsRunner(hands, bundle: "com.apple.Terminal"))
}

private func leftoverIsRefused(_ runner: ParentToolRunner, _ hands: FakeHands) async -> Bool {
    let spent = await runner.execute(name: typing.name, argumentsJSON: typing.arguments)
    return spent.output.hasPrefix("approval_required:") && hands.injected.isEmpty
}

@MainActor private func classicRound(
    _ tools: any ParentToolExecuting, heard: String
) async -> ClassicRuntime.ActedRound {
    let runtime = ClassicRuntime(
        transcriber: FakeTranscriber(), synthesizer: ScriptedSynth(),
        chat: ScriptedChat(), thread: ScriptedThread())
    runtime.parentGuard = ParentToolGuard(approvals: ScriptedApprovals(answer: true))
    // Its own task: the seam cancels whichever task runs the call.
    return await Task {
        await runtime.actRound([typing], said: "", heard: heard, using: tools, language: .en, unverified: [])
    }.value
}

@Suite struct WithdrawRevokes {
    @Test func revokeTakesTheGrantedAndThePendingTicketOfThatCallOnly() {
        let tickets = ApprovalTickets()
        let cut = ApprovalTickets.Ticket(name: "type_text", arguments: #"{"text":"a"}"#, pid: 7)
        let other = ApprovalTickets.Ticket(name: "type_text", arguments: #"{"text":"b"}"#, pid: 7)
        tickets.issue(cut)
        tickets.issue(other)
        tickets.park(cut, id: "r1")

        tickets.revoke(name: cut.name, arguments: cut.arguments)
        tickets.grant(id: "r1")

        #expect(!tickets.redeem(cut), "the cut call's ticket, granted or pending, is gone")
        #expect(tickets.redeem(other), "a different call keeps its ticket")
    }

    @Test func revokeMatchesWhateverPidTheTicketWasBoundTo() {
        let tickets = ApprovalTickets()
        let bound = ApprovalTickets.Ticket(name: "click", arguments: #"{"id":3}"#, pid: 9, node: 4, generation: 2)
        tickets.issue(bound)
        tickets.revoke(name: "click", arguments: #"{"id":3}"#)
        #expect(!tickets.redeem(bound))
    }

    // The workbook a write lands in is bound into its ticket after the
    // sheet; the revoke by name and arguments still has to find it.
    @Test func aSpreadsheetWriteGrantGoesWithItsCall() async {
        let write = ToolCallRef(
            id: "1", name: "sheet_write", arguments: #"{"app":"excel","range":"A1","values":"[[1]]"}"#)
        func grantedRunner() async -> (ParentToolRunner, RecordingSheets) {
            let sheets = RecordingSheets()
            let runner = ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []), sheets: sheets)
            if let asked = runner.approval(for: write, said: "") { runner.granted(await runner.bound(asked)) }
            return (runner, sheets)
        }

        // Control: the same grant, kept, is spendable.
        let (kept, keptSheets) = await grantedRunner()
        let wrote = await kept.execute(name: write.name, argumentsJSON: write.arguments)
        #expect(wrote.ok && keptSheets.writes == 1, "the control write did not go through: \(wrote.output)")

        let (dropped, droppedSheets) = await grantedRunner()
        dropped.withdraw(write)
        let spent = await dropped.execute(name: write.name, argumentsJSON: write.arguments)
        #expect(!spent.ok && droppedSheets.writes == 0, "the dropped write's grant was still spendable")
    }

    @Test func theCompositeWithdrawsFromEveryRunner() {
        let first = WithdrawRecorder(), second = WithdrawRecorder()
        CompositeParentTools([first, second]).withdraw(typing)
        #expect(first.withdrawn == [typing.id] && second.withdrawn == [typing.id])
    }

    @Test func aBrowserOpenTicketIsFoundByTheAddressItResolvedTo() async {
        let rig = makeToolRig()
        let open = rig.call("browser_open", #"{"url":"https://sf.example/"}"#)
        #expect(rig.runner.approval(for: open, said: "abre sf.example") == nil, "named: issued without a sheet")

        rig.runner.withdraw(open)

        let spent = await rig.runner.execute(name: open.name, argumentsJSON: open.arguments)
        #expect(spent.output.hasPrefix("approval_required:"))
    }
}

/// Cells already filled, so a write needs the sheet and its ticket.
private final class RecordingSheets: SpreadsheetDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var writes: Int { lock.withLock { count } }
    func active() async -> SheetApp? { .excel }
    func workbook(_ app: SheetApp) async throws -> String { "/tmp/libro.xlsx" }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { [["ya hay"]] }
    func write(
        _ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String
    ) async throws -> SheetWriteReceipt {
        lock.withLock { count += 1 }
        return SheetWriteReceipt(readBack: [])
    }
}

private final class WithdrawRecorder: ParentToolExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    var withdrawn: [String] { lock.withLock { ids } }
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { false }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome { .failed(.notFound(name)) }
    func withdraw(_ call: ToolCallRef) { lock.withLock { ids.append(call.id) } }
}

// Karen's Q1 condition: option A fails open if a future caller forgets
// `withdraw`, so the sources are scanned for it. Every place that runs the
// gate and then may drop the call before `execute` must withdraw on that
// branch.