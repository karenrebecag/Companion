import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func workRoutingTests() {
    testTheNativeLaneCannotSearchTheWeb()
    testACliLaneCan()
    testWorkGoesToTheMostCapableInstalled()
    testATieKeepsWhatYouPicked()
    testNothingInstalledMeansTheNativeLane()
    testRoutingIsVisibleWhenItOverrides()
}

private let claude = ExecutorDescriptor(
    id: .claudeCode, shortName: "claude", title: "Claude Code",
    kind: .detectedCLI)

@MainActor func testTheNativeLaneCannotSearchTheWeb() {
    // Lo que le paso a Karen: el desplegable decia "Nativo" — el DEFAULT — y
    // el encargo corrio en el unico carril sin busqueda web, con Claude Code
    // instalado y pagado al lado.
    expect(!ExecutorCatalog.native.capabilities.contains(.web),
           "el carril nativo no busca en la web por si mismo")
    expect(ExecutorCatalog.native.capabilities.contains(.files),
           "pero si tiene archivos")
    expect(ExecutorCatalog.native.capabilities.contains(.places),
           "y lugares, que no necesitan clave")
}

@MainActor func testACliLaneCan() {
    // Verificado contra la documentacion del CLI y contra los dos repos:
    // Claude Code trae WebSearch y WebFetch, y ambos codigos ya las pasan
    // en --allowedTools.
    expect(claude.capabilities.contains(.web),
           "Claude Code trae busqueda web incluida en la suscripcion")
}

@MainActor func testWorkGoesToTheMostCapableInstalled() {
    // La regla del prototipo, sin el vendor cableado: el carril de charla y el
    // de trabajo son elecciones distintas.
    let chosen = WorkRouting.executor(
        selected: .native, installed: [ExecutorCatalog.native, claude])
    expectEq(chosen, .claudeCode,
             "con un carril mas capaz instalado, el encargo se va ahi")
}

@MainActor func testATieKeepsWhatYouPicked() {
    // Ser igual de capaz no es razon para mover el trabajo.
    let twin = ExecutorDescriptor(
        id: .hermes, shortName: "hermes", title: "Hermes", kind: .detectedCLI)
    let chosen = WorkRouting.executor(
        selected: .claudeCode, installed: [claude, twin])
    expectEq(chosen, .claudeCode, "empate: se respeta tu eleccion")
}

@MainActor func testNothingInstalledMeansTheNativeLane() {
    let chosen = WorkRouting.executor(
        selected: .native, installed: [ExecutorCatalog.native])
    expectEq(chosen, .native, "sin nada mas, el encargo corre donde pueda")
}

@MainActor func testRoutingIsVisibleWhenItOverrides() {
    // El prototipo lo decia en la linea de estado. Un ruteo invisible es la
    // app decidiendo a tus espaldas.
    expect(WorkRouting.overrides(selected: .native, chosen: .claudeCode),
           "cuando el trabajo cambia de carril, se anuncia")
    expect(!WorkRouting.overrides(selected: .native, chosen: .native),
           "y cuando no cambia, no se molesta al usuario")
}
