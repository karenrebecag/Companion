import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Darwin
import Foundation
import Testing

// `HandsCaller.lineage(of:)` walks the parent chain via `sysctl`'s
// `kinfo_proc`. A spawned child (`/bin/sleep`) is the easiest way to
// exercise the chain: the test process is the child's parent, and the
// chain terminates at the init/launchd ancestor. Asserting the chain
// on both sides proves the walk returns every step instead of just
// the head, and that a partial chain (the unresolvable top) is the
// documented fall-through, not a crash.

@Test func handsCallerLineageFromSpawnedChildCoversTheChain() async throws {
    // `/bin/sleep 5` is a child the test process spawns; the parent's
    // lineage covers the test pid and (usually) one or two ancestors.
    // The child's lineage covers the child and the chain up to its
    // parent, which terminates at getpid().
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["5"]
    try child.run()
    defer { child.terminate() }
    let own = ProcessInfo.processInfo.processIdentifier
    let childLineage = HandsCaller.lineage(of: child.processIdentifier)
    expect(childLineage.contains(child.processIdentifier), "lineage(child): contiene al hijo \(childLineage)")
    let ownLineage = HandsCaller.lineage(of: own)
    expect(childLineage.isSuperset(of: ownLineage),
           "lineage(child): cubre lineage del padre \(childLineage) vs \(ownLineage)")
    expect(ownLineage.contains(own), "lineage(parent): contiene al padre")
    expectEq(HandsCaller.lineage(of: nil), [], "nil: vacio")
    expectEq(HandsCaller.lineage(of: -1), [], "pid invalido: vacio")
    expectEq(HandsCaller.lineage(of: Int32.max), [], "pid inexistente: vacio")
}
