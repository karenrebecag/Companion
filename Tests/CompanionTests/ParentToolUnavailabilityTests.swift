import CompanionCore
import CompanionServices
import Foundation
import Testing

// Wave 20b D4: the runner says WHY a known tool is not served right now.
@Test @MainActor func parentToolUnavailabilityTests() {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let seeFn: (@Sendable (String?) async -> ScreenBrief?)? = { _ in ScreenBrief(summary: "x") }
    func runner(trusted: Bool, front: Bool, see: Bool = true) -> ParentToolRunner {
        ParentToolRunner(
            workspace: FakeWorkspaceOpener(),
            hands: ScreenHands(
                injector: hands, reader: hands, keys: hands, windows: hands,
                trusted: { trusted }, target: { 7 }, bundleID: { _ in "com.apple.Notes" },
                selfInFront: { front }, see: see ? seeFn : nil))
    }
    expectEq(runner(trusted: true, front: true).unavailability(for: "type_text"), "self_in_front",
             "delante: self_in_front")
    expectEq(runner(trusted: true, front: true).unavailability(for: "see"), "self_in_front",
             "delante: see tambien")
    expectEq(runner(trusted: false, front: true).unavailability(for: "type_text"), "needs_accessibility",
             "sin permiso manda sobre estar delante")
    expectEq(runner(trusted: true, front: false, see: false).unavailability(for: "see"), "not_available",
             "sin vision: not_available")
    expect(runner(trusted: true, front: false).unavailability(for: "type_text") == nil,
           "lista: nada que decir")
    expect(runner(trusted: true, front: true).unavailability(for: "nope") == nil,
           "un nombre que no es tool no tiene razon")
    expectEq(ParentToolRunner(workspace: FakeWorkspaceOpener()).unavailability(for: "look"),
             "not_available", "sin manos cableadas: not_available")
    expect(ParentToolRunner(workspace: FakeWorkspaceOpener()).unavailability(for: "open_app") == nil,
           "una tool sin manos sigue lista")
}
