import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionUITestSupport
import CompanionTestKit

// approval-ticket-on-cut, typed chat: its own gate grants without the
// voice guard, and a turn that stopped being current breaks out after the
// gate. The ticket goes with it, whether a sheet's yes or the user's own
// words earned it.

private let typing = ToolCallRef(id: "c1", name: "type_text", arguments: #"{"text":"ls -la"}"#)

@Suite struct ChatTicketOnCut {
    @Test @MainActor func aChatTurnCutAfterTheSheetSaidYesLeavesNoTicket() async {
        let rig = ChatRig(cutAt: .granted, draft: "resume esto")
        rig.vm.send()
        await pumpUntil("the sheet is up") { rig.vm.pendingApproval != nil }

        rig.vm.answerApproval(true)
        await rig.waitForTheCut()

        #expect(await rig.leftoverIsRefused(), "the cut chat turn's yes is still spendable")
    }

    @Test @MainActor func aChatTurnCutAfterTheUserSaidItLeavesNoTicket() async {
        let rig = ChatRig(cutAt: .approval, draft: "escribe ls -la")
        rig.vm.send()

        await rig.waitForTheCut()

        #expect(rig.vm.pendingApproval == nil, "words the user said need no sheet")
        #expect(await rig.leftoverIsRefused(), "the ticket issued for the user's words outlived the cut")
    }
}

@MainActor private struct ChatRig {
    let hands = FakeHands(field: FocusedField(app: "Terminal", pid: 7))
    let runner: ParentToolRunner
    let cut = CutMark()
    let vm: ChatViewModel

    init(cutAt point: CuttingParentTools.Point, draft: String) {
        runner = handsRunner(hands, bundle: "com.apple.Terminal")
        let cut = self.cut
        let tools = CuttingParentTools(runner, at: point) {
            CuttingParentTools.cancelCurrentTask()
            cut.mark()
        }
        let chat = FakeChatProvider(replies: [.success([.toolCalls([typing])]), .success([.text("Listo.")])])
        vm = primed(chat: chat, parentTools: tools, approvals: FakeApprovals())
        vm.draft = draft
    }

    // The turn runs on the main actor and does not suspend between the gate
    // and its own cancel check, so once the test runs again the turn has
    // already dropped the call. Waiting for `busy` instead never ends: the
    // seam cancels the turn's task, which nothing in a test resets.
    func waitForTheCut() async {
        await pumpUntil("the turn is cut after the gate") { cut.isMarked }
    }

    func leftoverIsRefused() async -> Bool {
        let spent = await runner.execute(name: typing.name, argumentsJSON: typing.arguments)
        return spent.output.hasPrefix("approval_required:") && hands.injected.isEmpty
    }
}

private final class CutMark: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false
    var isMarked: Bool { lock.withLock { marked } }
    func mark() { lock.withLock { marked = true } }
}
