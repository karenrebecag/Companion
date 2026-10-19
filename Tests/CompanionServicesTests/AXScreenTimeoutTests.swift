import CompanionTestKit
import Foundation
import Testing

// Security review of #352 (HIGH-1): an element the walk touches without a
// messaging timeout waits the AX default (about 6 s) on a beachballing app, and
// the walk's budget cannot cut a call that is already blocked. The live walk
// is not testable without Accessibility, so its source is checked.
@Test func everyElementTheWalkTouchesHasAMessagingTimeout() throws {
    let root = try #require(Conformance.repoRoot())
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/CompanionServices/Accessibility/AXScreen.swift"),
        encoding: .utf8)
    expect(source.contains("func kind(of element: AXUIElement) -> ScreenKind {\n        LiveAXTree.bounded(element)"),
           "kind pone el timeout al primer contacto")
    expect(source.contains("func details(of element: AXUIElement, readValue: Bool) -> ScreenDetails {\n        LiveAXTree.bounded(element)"),
           "details pone el timeout al primer contacto")
    expect(source.contains("func value(of element: AXUIElement) -> String {\n        LiveAXTree.bounded(element)"),
           "value pone el timeout al primer contacto")
    expect(source.contains("bounded(window)"), "la ventana raíz lleva timeout")
    expect(source.contains("bounded(other)"), "las ventanas de diálogo llevan timeout")
    expect(!source.contains("for child in children { AXUIElementSetMessagingTimeout"),
           "los hijos no se marcan todos por adelantado: una tabla de 5000 filas costaría 5000 llamadas")
}

// The clock starts before priming and window discovery: the settle and the
// lookups are part of the time the walk promises (review 16, HIGH).
@Test func theBudgetClockStartsBeforePriming() throws {
    let root = try #require(Conformance.repoRoot())
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/CompanionServices/Accessibility/AXScreen.swift"),
        encoding: .utf8)
    let clock = try #require(source.range(of: "let start = ContinuousClock.now"))
    let priming = try #require(source.range(of: "if prime(application, pid: pid"))
    expect(clock.lowerBound < priming.lowerBound, "el reloj arranca antes del settle")
}
