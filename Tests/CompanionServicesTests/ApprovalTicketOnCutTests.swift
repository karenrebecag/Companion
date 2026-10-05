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

@Suite struct ApprovalTicketOnCut {
    @Test @MainActor func aClassicCallCutAfterTheSheetSaidYesLeavesNoTicket() async {
        let (hands, runner) = terminal()
        let acted = await classicRound(CuttingParentTools(runner, at: .granted), heard: "")

        #expect(acted.turns.last?.content == ContractError.interrupted.wire)
        #expect(await leftoverIsRefused(runner, hands), "the cut call's yes is still spendable")
    }

    @Test @MainActor func aClassicCallCutAfterTheUserSaidItLeavesNoTicket() async {
        let (hands, runner) = terminal()
        let acted = await classicRound(CuttingParentTools(runner, at: .approval), heard: "escribe ls -la")

        #expect(acted.turns.last?.content == ContractError.interrupted.wire)
        #expect(await leftoverIsRefused(runner, hands), "the ticket issued for the user's words outlived the cut")
    }

    @Test @MainActor func aRealtimeCallCutAfterTheSheetSaidYesLeavesNoTicket() async {
        let (hands, runner) = terminal()
        let tools = CuttingParentTools(runner, at: .granted)
        let gate = ParentToolGuard(approvals: ScriptedApprovals(answer: true))

        let outcome = await Task {
            await RealtimeRuntime.act(typing, gate: gate, said: "", language: .en, tools: tools)
        }.value

        #expect(outcome.output == ContractError.interrupted.wire)
        #expect(await leftoverIsRefused(runner, hands), "the cut realtime call's yes is still spendable")
    }

    @Test @MainActor func aBridgeCallWhosePeerLeftAfterTheYesLeavesNoTicket() async {
        let (hands, runner) = terminal()
        let pair = BridgePair()
        let tools = CuttingParentTools(runner, at: .granted) { pair.connection.close() }
        let session = BridgeSession(
            tools: tools, guard: ParentToolGuard(approvals: ScriptedApprovals(answer: true)),
            token: { "tok" }, language: { .en }, accessibility: { true })
        let serving = Task.detached { await session.serve(pair.connection) }
        pair.send(hello(1))
        _ = pair.readLine()
        pair.send(#"{"id":2,"method":"call","params":{"name":"type_text","arguments":{"text":"ls -la"}}}"#)
        await serving.value

        #expect(await leftoverIsRefused(runner, hands), "a yes for a peer that left is still spendable")
    }
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
@Suite struct WithdrawOnEveryCutBranch {
    /// Where a gate that can hand out a ticket is run.
    private static var gateCall: Regex<(Substring, Substring?, Substring?)> {
        #/(parentGuard|gate|guardian)\.(check|verdict)\(|await gate\(call/#
    }
    /// A branch that drops the call after the gate. Only these two
    /// spellings are known: a lane that drops another way (a throw, a
    /// `return nil`) is invisible here and needs its own entry.
    private static var dropBranch: Regex<Substring> { #/Task\.isCancelled|return \.dropped/# }

    /// The call the gate was handed, so the withdraw must name the same one.
    private static var gatedCall: Regex<(Substring, Substring)> {
        #/(?:\.(?:check|verdict)|await gate)\(\s*(\w+)/#
    }

    /// The drops between a gate call and the next `execute` with no
    /// `withdraw(<that call>)` within two logical lines: a branch is that
    /// short in every lane, and a looser window would let one withdraw
    /// vouch for another branch.
    static func unwithdrawnDrops(in lines: [String]) -> [String] {
        var misses: [String] = []
        var gate: (at: Int, call: String)?
        for (index, line) in lines.enumerated() {
            if line.contains(gateCall) {
                gate = (index, line.firstMatch(of: gatedCall).map { String($0.1) } ?? "")
                continue
            }
            guard let start = gate else { continue }
            if line.contains("execute(name:") { gate = nil; continue }
            guard line.contains(dropBranch) else { continue }
            let near = lines[max(start.at + 1, index - 2)...min(lines.count - 1, index + 2)]
            if !near.contains(where: { $0.contains("withdraw(\(start.call))") }) { misses.append(line) }
        }
        return misses
    }

    @Test func everyCutBranchAfterTheGateWithdraws() throws {
        let root = try #require(Conformance.repoRoot())
        let files = Conformance.swiftFiles(in: root.appendingPathComponent("Sources"))
        var callers: [String] = []
        var misses: [String] = []
        for file in files {
            let lines = Conformance.logicalLines(of: file)
            guard lines.contains(where: { $0.contains(Self.gateCall) }) else { continue }
            callers.append(file.lastPathComponent)
            misses += Self.unwithdrawnDrops(in: lines).map { "\(file.lastPathComponent): \($0)" }
        }
        // The scan has to keep finding the four lanes, or it passes on nothing.
        for lane in ["ClassicRuntime+Act.swift", "RealtimeRuntime.swift",
                     "BridgeSession+Calls.swift", "ChatViewModel+Turn.swift"] {
            #expect(callers.contains(lane), "the scan no longer finds the gate in \(lane)")
        }
        #expect(misses.isEmpty, "a drop after the gate leaves its ticket: \(misses)")
    }

    @Test func theScanCatchesADropThatForgetsToWithdraw() {
        let forgets = [
            "if let denied = await parentGuard.check(call, said: s, language: l, tools: t) {",
            "} else if Task.isCancelled {",
            "outcome = .failed(.interrupted)",
            "} else {",
            "outcome = await t.execute(name: call.name, argumentsJSON: call.arguments)",
        ]
        #expect(Self.unwithdrawnDrops(in: forgets).count == 1)
        let withdraws = forgets.enumerated().map { $0.offset == 2 ? "t.withdraw(call); " + $0.element : $0.element }
        #expect(Self.unwithdrawnDrops(in: withdraws).isEmpty)
        let wrongCall = forgets.enumerated().map { $0.offset == 2 ? "t.withdraw(other); " + $0.element : $0.element }
        #expect(Self.unwithdrawnDrops(in: wrongCall).count == 1, "a withdraw of another call vouched for this one")
    }
}
