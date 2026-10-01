@testable import CompanionUI
import CompanionTestKit
import Testing

// Spec 16p §4.2: the welcome is the only first-run flow. The legacy
// onboarding was the fallback when the root got no welcome model; with it
// retired, a missing key always routes back to the welcome.

@Test @MainActor func rootScreenTests() {
    expectEq(RootScreen.pick(welcomeDone: false, needsKey: false), .welcome,
             "raíz: sin terminar la bienvenida, se ve la bienvenida")
    expectEq(RootScreen.pick(welcomeDone: false, needsKey: true), .welcome,
             "raíz: primera vez y sin key, bienvenida")
    expectEq(RootScreen.pick(welcomeDone: true, needsKey: true), .welcome,
             "raíz: bienvenida vista pero sin key, vuelve a la bienvenida (nunca otro flujo)")
    expectEq(RootScreen.pick(welcomeDone: true, needsKey: false), .main,
             "raíz: bienvenida hecha y key lista, la ventana principal")
    expectEq(RootScreen.allCases, [.welcome, .main],
             "raíz: solo dos pantallas, no hay tercer flujo de arranque")
}
