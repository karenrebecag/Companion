import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// The merge of main (20c D1) into feat/ui-gap (16q-1): a spoken yes must pass
// BOTH designs. 16q-1 binds it to her own words in the hold after the voice
// asked; 20c D1 lets the voice settle only what is low risk. A request that
// passes the first and fails the second still takes the click.

@Test @MainActor func mergedSpokenYesTests() async {
    await testAnAnnouncedClearYesStillNeedsTheClickForAHighRiskTool()
    await testAnAnnouncedClearYesNeedsTheClickForABrowserAction()
    await testAnAnnouncedClearYesNeedsTheClickForTheBridgesHands()
    await testTheSameYesResolvesALowRiskTool()
}

@MainActor private func answerToAClearYes(tool: String) async -> SpokenApproval {
    let jobs = GatedJob()
    let h = await q1Classic(jobs)
    await q1AskedAndSaid(h, jobs, "r1", tool: tool)
    await q1HeldKey(h)
    await h.session.noteHeard("sí, dale", pressed: await h.session.timeline.pressed)
    let answer = await h.session.answerPendingApproval(true)
    jobs.open()
    await h.session.hangUp()
    return answer
}

@MainActor func testAnAnnouncedClearYesStillNeedsTheClickForAHighRiskTool() async {
    for tool in ["run_shell", "Bash", "write_file", "sheet_write", "open_url"] {
        expectEq(await answerToAClearYes(tool: tool), .needsClick,
                 "fusion: \(tool) anunciado y con un si claro sigue pidiendo el clic")
    }
}

@MainActor func testAnAnnouncedClearYesNeedsTheClickForABrowserAction() async {
    for tool in BrowserTool.allCases.map(\.rawValue) {
        expectEq(await answerToAClearYes(tool: tool), .needsClick,
                 "fusion: la herramienta del navegador \(tool) nunca se aprueba por voz")
    }
}

@MainActor func testAnAnnouncedClearYesNeedsTheClickForTheBridgesHands() async {
    expectEq(await answerToAClearYes(tool: BridgePolicy.sessionApprovalTool), .needsClick,
             "fusion: la concesion del puente nunca se aprueba por voz")
}

@MainActor func testTheSameYesResolvesALowRiskTool() async {
    expectEq(await answerToAClearYes(tool: "find_places"), .resolved,
             "fusion: el mismo si, para una peticion de bajo riesgo, resuelve")
}
