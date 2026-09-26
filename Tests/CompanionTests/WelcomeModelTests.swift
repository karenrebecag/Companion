import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 16c: the welcome's view model over a fake machine. Rows update live,
// the meter opens Continue once it hears something, the hold is a real one,
// the greeting speaks once, and finishing is remembered.

@Test @MainActor func welcomeModelTests() async {
    await testRowsFollowTheMachine()
    await testTheMeterOpensContinueOnceItHearsSomething()
    await testTheLastScreenWaitsForAHoldThatSentWords()
    await testTheGreetingSpeaksOnce()
    await testFinishingIsRemembered()
}

private final class FakeWelcomeDevices: WelcomeDevices, @unchecked Sendable {
    private let lock = NSLock()
    private var grants: Set<WelcomePermission>
    private var said: [String] = []
    let levels: [Double]

    init(granted: Set<WelcomePermission> = [], levels: [Double] = []) {
        self.grants = granted
        self.levels = levels
    }

    var greetings: [String] { lock.withLock { said } }
    func grant(_ permission: WelcomePermission) { lock.withLock { _ = grants.insert(permission) } }

    func granted(_ permission: WelcomePermission) async -> Bool { lock.withLock { grants.contains(permission) } }
    func request(_ permission: WelcomePermission) async -> Bool {
        lock.withLock { _ = grants.insert(permission) }
        return true
    }
    func micLevels() -> AsyncStream<Double> {
        let values = levels
        return AsyncStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }
    func greet(_ text: String, language: AppLanguage) async { lock.withLock { said.append(text) } }
}

@MainActor private func model(_ devices: FakeWelcomeDevices, key: Bool = true, defaults: UserDefaults? = nil) -> WelcomeModel {
    WelcomeModel(devices: devices, keyReady: { key }, defaults: defaults ?? scratchDefaults())
}

private func scratchDefaults() -> UserDefaults {
    let name = "welcome-tests-\(UUID().uuidString)"
    return UserDefaults(suiteName: name) ?? .standard
}

@MainActor func testRowsFollowTheMachine() async {
    let devices = FakeWelcomeDevices(granted: [.microphone])
    let welcome = model(devices)
    await welcome.refresh()
    expectEq(welcome.facts.granted, [.microphone], "filas: lo concedido")
    devices.grant(.accessibility)
    await welcome.refresh()
    expectEq(welcome.facts.granted, [.microphone, .accessibility], "filas: detecta el cambio")
    await welcome.request(.speechRecognition)
    expect(welcome.facts.granted.contains(.speechRecognition), "filas: pedir actualiza")
    expect(welcome.facts.keyReady, "clave: la lee del chat")
}

@MainActor func testTheMeterOpensContinueOnceItHearsSomething() async {
    let quiet = model(FakeWelcomeDevices(levels: [0.01, 0.02]))
    await quiet.listen()
    expect(!quiet.facts.micHeard, "micro: el ruido de fondo no cuenta")
    let voice = model(FakeWelcomeDevices(levels: [0.01, WelcomeModel.heardLevel + 0.1]))
    await voice.listen()
    expect(voice.facts.micHeard, "micro: una voz sí")
    expect(voice.level > WelcomeModel.heardLevel, "micro: la barra muestra el nivel")
}

@MainActor func testTheLastScreenWaitsForAHoldThatSentWords() async {
    let welcome = model(FakeWelcomeDevices())
    welcome.observe(.processing(.pending))
    expect(!welcome.facts.holdDone, "hold: fuera de su pantalla no cuenta")
    welcome.jump(to: .yourTurn)
    welcome.observe(.listening)
    expect(!welcome.facts.holdDone, "hold: apretar no basta")
    welcome.observe(.processing(.pending))
    expect(welcome.facts.holdDone, "hold: soltar con palabras sí")
    welcome.next()
    expect(welcome.flow.finished, "hold: termina la bienvenida")
}

@MainActor func testTheGreetingSpeaksOnce() async {
    let devices = FakeWelcomeDevices()
    let welcome = model(devices)
    await welcome.greet()
    await welcome.greet()
    expectEq(devices.greetings.count, 1, "saludo: una vez")
    welcome.reopen()
    await welcome.greet()
    expectEq(devices.greetings.count, 2, "saludo: reabrir la bienvenida saluda otra vez")
}

@MainActor func testFinishingIsRemembered() async {
    let defaults = scratchDefaults()
    let welcome = model(FakeWelcomeDevices(), defaults: defaults)
    expect(!welcome.done, "primera vez: sin ver")
    welcome.jump(to: .yourTurn)
    welcome.skip()
    expect(welcome.done, "saltar el final también la da por vista")
    let again = model(FakeWelcomeDevices(), defaults: defaults)
    expectEq(again.flow.step, .keys, "la próxima vez, solo si falta la clave")
    again.jump(to: .yourTurn)
    again.skip()
    again.resumeKeys()
    expectEq(again.flow.step, .keys, "clave perdida después de verla: vuelve a claves")
    expect(!again.flow.finished, "y no está terminada")
    again.reopen()
    expectEq(again.flow.step, .cover, "reabrir desde Ajustes: desde la portada")
    expect(!again.done, "reabierta: se muestra")
}
