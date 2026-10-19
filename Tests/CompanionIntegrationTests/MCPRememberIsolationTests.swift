import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Integration fix round 1, item 1 (C3): the merge routes the realtime MCP
// request through `ParentToolGuard.answer`, which consults the remembered
// decisions keyed by tool name. An MCP server names its own tools, so a
// remote `run_shell` must never inherit what the user remembered for the
// local one, in either direction, and must never be remembered itself.

@Test @MainActor func mcpRememberIsolationTests() async {
}

private let lsArgs = #"{"command":"ls"}"#

private func localShell(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "ls", inputJSON: #"{"command":"ls -la"}"#)
}

private func mcpShell(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "run_shell", inputJSON: lsArgs, isMCP: true)
}

/// A provider that remembers "yes" for anything it is asked about: only the
/// guard's own check can keep an MCP request away from it.
private final class RemembersEverything: ApprovalsProvider, @unchecked Sendable {
    var asked: [String] = []
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        asked.append(approval.requestId)
        return ApprovalResponse(requestId: approval.requestId, approved: false)
    }
    func resolve(requestId: String, approved: Bool) async -> Bool { false }
    func remembered(_ approval: ApprovalRequest) async -> Bool? { true }
}

private func resolveWhenParked(
    _ actor: Approvals, _ id: String, approved: Bool, _ label: String
) async {
    var done = false
    await pumpUntilAsync(label) {
        if !done { done = await actor.resolve(requestId: id, approved: approved, remember: true) }
        return done
    }
}

/// Remembers `run_shell(ls *)` for the local tool with `approved`.
private func actorRememberingLocalShell(_ approved: Bool) async -> Approvals {
    let actor = Approvals(clock: RealtimeClock())
    let parked = Task.detached { await actor.request(localShell("local")) }
    await resolveWhenParked(actor, "local", approved: approved, "mcp recordar: la local espera")
    _ = await parked.value
    expectEq(await actor.remembered(localShell("again")), approved, "mcp recordar: previo, la regla local existe")
    return actor
}
