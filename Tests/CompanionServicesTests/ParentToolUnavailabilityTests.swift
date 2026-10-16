import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 20b D4: the runner says WHY a known tool is not served right now.
@Test @MainActor func parentToolUnavailabilityTests() {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let seeFn: (@Sendable (SeeRequest) async -> ScreenBrief?)? = { _ in ScreenBrief(summary: "x") }
    func runner(trusted: Bool, see: Bool = true) -> ParentToolRunner {
        ParentToolRunner(
            workspace: FakeWorkspaceOpener(),
            hands: ScreenHands(
                injector: hands, reader: hands, keys: hands, windows: hands,
                trusted: { trusted }, target: { 7 }, bundleID: { _ in "com.apple.Notes" },
                see: see ? seeFn : nil))
    }
    expectEq(runner(trusted: false).unavailability(for: "type_text"), "needs_accessibility",
             "sin permiso: needs_accessibility")
    expectEq(runner(trusted: true, see: false).unavailability(for: "see"), "not_available",
             "sin vision: not_available")
    expect(runner(trusted: true).unavailability(for: "type_text") == nil,
           "lista: nada que decir")
    expect(runner(trusted: true).unavailability(for: "nope") == nil,
           "un nombre que no es tool no tiene razon")
    expectEq(ParentToolRunner(workspace: FakeWorkspaceOpener()).unavailability(for: "look"),
             "not_available", "sin manos cableadas: not_available")
    expect(ParentToolRunner(workspace: FakeWorkspaceOpener()).unavailability(for: "open_app") == nil,
           "una tool sin manos sigue lista")
}
