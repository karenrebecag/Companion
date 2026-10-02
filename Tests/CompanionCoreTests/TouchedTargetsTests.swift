import CompanionCore
import CompanionTestKit
import Testing

// Brief isla-maquetacion-incredible, F1: look, click and the other tools
// have no target, so `ParentTool.target` is "" and the reel drew an empty
// chip (a bare 230-wide bar). The reel only keeps something to name.

@Test @MainActor func touchedNeverKeepsAnEmptyTarget() {
    var m = SessionMachine()
    _ = m.handle(.typedSubmitted)
    _ = m.handle(.parentActing(targets: ["Notes", ""]))
    _ = m.handle(.parentActed)
    _ = m.handle(.parentActing(targets: ["  "]))
    _ = m.handle(.parentActed)
    _ = m.handle(.parentActing(targets: [""]))
    expectEq(m.projection.touched, ["Notes"], "solo lo que tiene nombre entra al carrete")
    expectEq(m.projection.kind, .processing(.toolExecuting), "una tool sin objetivo sigue contando como acción")
}

@Test func aTargetIsNamedOnlyWithText() {
    expect(ParentTool.names("Notes"), "con texto")
    for blank in ["", " ", "\n\t "] {
        expect(!ParentTool.names(blank), "en blanco: \(blank.debugDescription)")
    }
}
