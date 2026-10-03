import CompanionCore
@testable import CompanionUI
import CompanionTestKit
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
    testAReopenedAppResumesOnTheSavedStep()
    testTheIntroIsNeverSaved()
    testFinishingForgetsTheSavedStep()
    testReopeningFromSettingsStartsOverAndSavesAgain()
    testAnUnknownSavedStepStartsFromTheCover()
    testGoingBackToTheIntroKeepsTheSavedStep()
    testAFinishedWelcomeIgnoresAStaleSavedStep()
    await testEveryResumableStepResumes()
    testSavedNamesAreTheOnDiskContract()
    await testScreenRecordingCountsOnlyOnceACaptureWorked()
    await testThePollProbesUntilACaptureWorks()
    await testARelaunchOntoPermissionsAsksAgainOnce()
    await testWithoutTheRelaunchRefocusNeverAsks()
    await testLeavingPermissionsDisarmsTheSecondAsk()
    await testTheSecondAskNeedsTheSwitchOn()
    await testTappingAllowProbesAfterTheAsk()
    await testALostGrantDropsTheRowUntilProbedAgain()
    await testLosingAPermissionAfterTheStepGoesBack()
    await testRefocusAndAllowProbeAVerifiedRowAfresh()
    await testAnyLostPermissionSendsTheNextStepsBack()
    await testThePollNeverSpendsTheSecondAsk()
    await testGoingBackToPermissionsDoesNotRearm()
    await testADenialAtThePromptLeavesTheRowOff()
    await testTwoRefocusesAtOnceAskOnce()
}

private final class FakeWelcomeDevices: WelcomeDevices, @unchecked Sendable {
    private let lock = NSLock()
    private var grants: Set<WelcomePermission>
    private var said: [String] = []
    private var asked: [WelcomePermission] = []
    private var probes = 0
    private var _captures = true
    private var _denies = false
    let levels: [Double]

    init(granted: Set<WelcomePermission> = [], levels: [Double] = []) {
        self.grants = granted
        self.levels = levels
    }

    var greetings: [String] { lock.withLock { said } }
    var requests: [WelcomePermission] { lock.withLock { asked } }
    var verifies: Int { lock.withLock { probes } }
    var captures: Bool {
        get { lock.withLock { _captures } }
        set { lock.withLock { _captures = newValue } }
    }
    func grant(_ permission: WelcomePermission) { lock.withLock { _ = grants.insert(permission) } }
    func revoke(_ permission: WelcomePermission) { lock.withLock { _ = grants.remove(permission) } }
    var denies: Bool {
        get { lock.withLock { _denies } }
        set { lock.withLock { _denies = newValue } }
    }

    func granted(_ permission: WelcomePermission) async -> Bool { lock.withLock { grants.contains(permission) } }
    func request(_ permission: WelcomePermission) async -> Bool {
        lock.withLock {
            asked.append(permission)
            if !_denies { _ = grants.insert(permission) }
            return !_denies
        }
    }
    func verifyScreenCapture() async -> Bool {
        lock.withLock {
            probes += 1
            return _captures
        }
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

// Incredible saves the page reached on every move into a resumable page and
// reopens there: macOS asks for a relaunch after Screen Recording, and the
// user must land back on the permissions step, not on the cover.

@MainActor func testAReopenedAppResumesOnTheSavedStep() {
    let defaults = scratchDefaults()
    let welcome = model(FakeWelcomeDevices(), defaults: defaults)
    welcome.jump(to: .keys)
    welcome.next()
    expectEq(welcome.flow.step, .permissions, "avanza a permisos")
    let relaunched = model(FakeWelcomeDevices(), defaults: defaults)
    expectEq(relaunched.flow.step, .permissions, "relanzada: vuelve al paso de permisos")
    relaunched.back()
    let again = model(FakeWelcomeDevices(), defaults: defaults)
    expectEq(again.flow.step, .keys, "volver atrás también se guarda")
}

@MainActor func testTheIntroIsNeverSaved() {
    let defaults = scratchDefaults()
    let welcome = model(FakeWelcomeDevices(), defaults: defaults)
    welcome.next()
    expectEq(welcome.flow.step, .hello, "en el saludo")
    let relaunched = model(FakeWelcomeDevices(), defaults: defaults)
    expectEq(relaunched.flow.step, .cover, "la introducción empieza otra vez desde la portada")
}

@MainActor func testFinishingForgetsTheSavedStep() {
    let defaults = scratchDefaults()
    let welcome = model(FakeWelcomeDevices(), defaults: defaults)
    welcome.jump(to: .yourTurn)
    welcome.skip()
    expect(welcome.done, "terminada")
    let relaunched = model(FakeWelcomeDevices(), defaults: defaults)
    expectEq(relaunched.flow.step, .keys, "terminada: sigue el camino de siempre, no el paso guardado")
    expect(defaults.object(forKey: WelcomeModel.stepKey) == nil, "terminada: el paso guardado se borra")
}

@MainActor func testReopeningFromSettingsStartsOverAndSavesAgain() {
    let defaults = scratchDefaults()
    let welcome = model(FakeWelcomeDevices(), defaults: defaults)
    welcome.jump(to: .yourTurn)
    welcome.skip()
    welcome.reopen()
    expectEq(welcome.flow.step, .cover, "reabierta: desde la portada")
    welcome.jump(to: .microphone)
    expectEq(defaults.string(forKey: WelcomeModel.stepKey), "microphone", "reabierta: guarda otra vez")
    let relaunched = model(FakeWelcomeDevices(), defaults: defaults)
    expectEq(relaunched.flow.step, .keys, "vista antes: relanzar no la reabre")
    let fresh = scratchDefaults()
    let first = model(FakeWelcomeDevices(), defaults: fresh)
    first.jump(to: .microphone)
    expectEq(model(FakeWelcomeDevices(), defaults: fresh).flow.step, .microphone, "saltar a un paso lo guarda")
}

@MainActor func testAnUnknownSavedStepStartsFromTheCover() {
    let defaults = scratchDefaults()
    defaults.set("gone", forKey: WelcomeModel.stepKey)
    expectEq(model(FakeWelcomeDevices(), defaults: defaults).flow.step, .cover, "valor desconocido: portada")
    for value in ["hello", "cover", ""] {
        defaults.set(value, forKey: WelcomeModel.stepKey)
        expectEq(model(FakeWelcomeDevices(), defaults: defaults).flow.step, .cover, "no reanudable \"\(value)\": portada")
    }
    defaults.set(3, forKey: WelcomeModel.stepKey)
    expectEq(model(FakeWelcomeDevices(), defaults: defaults).flow.step, .cover, "un número no es un nombre: portada")
}

@MainActor func testGoingBackToTheIntroKeepsTheSavedStep() {
    let defaults = scratchDefaults()
    let welcome = model(FakeWelcomeDevices(), defaults: defaults)
    welcome.jump(to: .keys)
    expectEq(defaults.string(forKey: WelcomeModel.stepKey), "keys", "claves: guardado")
    welcome.back()
    expectEq(welcome.flow.step, .hello, "atrás al saludo")
    expectEq(defaults.string(forKey: WelcomeModel.stepKey), "keys", "la introducción no escribe ni borra")
    expectEq(model(FakeWelcomeDevices(), defaults: defaults).flow.step, .keys, "relanzada: el último paso alcanzado")
}

@MainActor func testAFinishedWelcomeIgnoresAStaleSavedStep() {
    let defaults = scratchDefaults()
    defaults.set(true, forKey: WelcomeModel.doneKey)
    defaults.set("permissions", forKey: WelcomeModel.stepKey)
    let welcome = model(FakeWelcomeDevices(), defaults: defaults)
    expect(welcome.done, "vista")
    expectEq(welcome.flow.step, .keys, "vista: un paso viejo no la reabre")
}

@MainActor func testEveryResumableStepResumes() async {
    let resumable: [WelcomeStep] = [.keys, .permissions, .holdKey, .microphone, .yourTurn]
    expectEq(WelcomeStep.allCases.filter(\.resumable), resumable, "los reanudables son estos")
    for step in resumable {
        let defaults = scratchDefaults()
        model(FakeWelcomeDevices(), defaults: defaults).jump(to: step)
        expectEq(model(FakeWelcomeDevices(), defaults: defaults).flow.step, step, "saltar a \(step) y relanzar")
    }
    let defaults = scratchDefaults()
    let walking = model(FakeWelcomeDevices(granted: Set(WelcomePermission.allCases)), defaults: defaults)
    walking.jump(to: .permissions)
    await walking.refresh()
    for expected in [WelcomeStep.holdKey, .microphone] {
        walking.next()
        expectEq(walking.flow.step, expected, "next llega a \(expected)")
        expectEq(model(FakeWelcomeDevices(), defaults: defaults).flow.step, expected, "next a \(expected) se guarda")
    }
}

@MainActor func testSavedNamesAreTheOnDiskContract() {
    for step in WelcomeStep.allCases {
        expectEq(WelcomeStep(savedName: step.savedName), step, "ida y vuelta: \(step)")
    }
    expectEq(WelcomeStep.allCases.map(\.savedName),
             ["cover", "hello", "keys", "permissions", "holdKey", "microphone", "yourTurn"],
             "los nombres guardados en disco no cambian")
}

// Gap 1b: Incredible's permissions step counts Screen Recording only when it
// is granted AND a capture was verified, asks again once when the app
// reopened straight onto that step, and sends a later step back to it when a
// permission is lost.

/// The app relaunched onto the saved permissions step, as macOS asks after
/// Screen Recording is granted.
@MainActor private func relaunchedOnPermissions(_ devices: FakeWelcomeDevices) -> WelcomeModel {
    let defaults = scratchDefaults()
    model(FakeWelcomeDevices(), defaults: defaults).jump(to: .permissions)
    let welcome = model(devices, defaults: defaults)
    expectEq(welcome.flow.step, .permissions, "relanzada en permisos")
    return welcome
}

@MainActor func testScreenRecordingCountsOnlyOnceACaptureWorked() async {
    let devices = FakeWelcomeDevices(granted: [.screenRecording])
    devices.captures = false
    let welcome = model(devices)
    welcome.jump(to: .permissions)
    await welcome.refresh()
    expect(!welcome.facts.granted.contains(.screenRecording), "pantalla: concedido sin captura no cuenta")
    expect(welcome.screenRecordingUnverified, "pantalla: encendido sin funcionar es su propio estado")
    devices.captures = true
    await welcome.refocused()
    expect(welcome.facts.granted.contains(.screenRecording), "pantalla: al volver, una captura que funciona cuenta")
    expect(!welcome.screenRecordingUnverified, "pantalla: verificado")
}

@MainActor func testThePollProbesUntilACaptureWorks() async {
    let devices = FakeWelcomeDevices(granted: [.screenRecording])
    devices.captures = false
    let welcome = model(devices)
    welcome.jump(to: .permissions)
    await welcome.refresh()
    await welcome.refresh()
    expectEq(devices.verifies, 2, "sondeo de 1 s: sin verificar, prueba en cada vuelta")
    devices.captures = true
    await welcome.refresh()
    await welcome.refresh()
    await welcome.refresh()
    expectEq(devices.verifies, 3, "verificado: el sondeo deja de probar")
    expect(devices.requests.isEmpty, "sondeo: no pide nada")
}

@MainActor func testARelaunchOntoPermissionsAsksAgainOnce() async {
    let devices = FakeWelcomeDevices(granted: [.screenRecording])
    devices.captures = false
    let welcome = relaunchedOnPermissions(devices)
    await welcome.refocused()
    expectEq(devices.requests, [.screenRecording], "relanzada: pide otra vez")
    await welcome.refocused()
    expectEq(devices.requests.count, 1, "solo una vez")
}

@MainActor func testWithoutTheRelaunchRefocusNeverAsks() async {
    let devices = FakeWelcomeDevices(granted: [.screenRecording])
    devices.captures = false
    let welcome = model(devices)
    welcome.jump(to: .permissions)
    await welcome.refocused()
    await welcome.refocused()
    expect(devices.requests.isEmpty, "llegar al paso caminando no arma el segundo pedido")
    expectEq(devices.verifies, 2, "al volver: vuelve a probar")
}

@MainActor func testLeavingPermissionsDisarmsTheSecondAsk() async {
    let devices = FakeWelcomeDevices(granted: [.screenRecording])
    devices.captures = false
    let welcome = relaunchedOnPermissions(devices)
    welcome.jump(to: .holdKey)
    welcome.jump(to: .permissions)
    await welcome.refocused()
    expect(devices.requests.isEmpty, "salir del paso desarma")
}

@MainActor func testTheSecondAskNeedsTheSwitchOn() async {
    let devices = FakeWelcomeDevices()
    let welcome = relaunchedOnPermissions(devices)
    await welcome.refocused()
    expect(devices.requests.isEmpty, "sin el interruptor encendido no pide solo")
    devices.grant(.screenRecording)
    devices.captures = false
    await welcome.refocused()
    expectEq(devices.requests, [.screenRecording], "encendido y sin captura: pide")
}

@MainActor func testTappingAllowProbesAfterTheAsk() async {
    let devices = FakeWelcomeDevices()
    let welcome = model(devices)
    welcome.jump(to: .permissions)
    await welcome.request(.screenRecording)
    expectEq(devices.requests, [.screenRecording], "tocar Permitir pide")
    expectEq(devices.verifies, 1, "y prueba una captura")
    expect(welcome.facts.granted.contains(.screenRecording), "verificado")
}

@MainActor func testALostGrantDropsTheRowUntilProbedAgain() async {
    let devices = FakeWelcomeDevices(granted: [.screenRecording])
    let welcome = model(devices)
    welcome.jump(to: .permissions)
    await welcome.refresh()
    expect(welcome.facts.granted.contains(.screenRecording), "verificado")
    devices.revoke(.screenRecording)
    await welcome.refresh()
    expect(!welcome.facts.granted.contains(.screenRecording), "revocado sale de la fila")
    devices.grant(.screenRecording)
    devices.captures = false
    await welcome.refresh()
    expect(!welcome.facts.granted.contains(.screenRecording), "concedido de nuevo: vuelve a probar y no basta")
    expectEq(devices.verifies, 2, "una prueba nueva tras la concesión nueva")
}

@MainActor func testLosingAPermissionAfterTheStepGoesBack() async {
    let devices = FakeWelcomeDevices(granted: Set(WelcomePermission.allCases))
    let welcome = model(devices)
    welcome.jump(to: .permissions)
    await welcome.refresh()
    welcome.next()
    expectEq(welcome.flow.step, .holdKey, "con todo concedido avanza")
    devices.revoke(.microphone)
    await welcome.refocused()
    expectEq(welcome.flow.step, .permissions, "perdido después: vuelve a permisos")
    devices.grant(.microphone)
    await welcome.refresh()
    welcome.jump(to: .yourTurn)
    devices.revoke(.accessibility)
    await welcome.refocused()
    expectEq(welcome.flow.step, .yourTurn, "en tu turno no retrocede (Incredible solo desde el paso siguiente)")
}

@MainActor func testRefocusAndAllowProbeAVerifiedRowAfresh() async {
    let devices = FakeWelcomeDevices(granted: [.screenRecording])
    let welcome = model(devices)
    welcome.jump(to: .permissions)
    await welcome.refresh()
    await welcome.refresh()
    expectEq(devices.verifies, 1, "verificado: el sondeo no vuelve a probar")
    await welcome.refocused()
    expectEq(devices.verifies, 2, "al volver: prueba aunque ya estaba verificado")
    devices.captures = false
    await welcome.refocused()
    expect(!welcome.facts.granted.contains(.screenRecording), "al volver: una captura rota saca la fila")
    expect(welcome.screenRecordingUnverified, "al volver: encendido sin funcionar")
    devices.captures = true
    await welcome.refresh()
    expectEq(devices.verifies, 4, "sin verificar: el sondeo vuelve a probar")
    await welcome.request(.screenRecording)
    expectEq(devices.verifies, 5, "tocar Permitir: prueba aunque ya estaba verificado")
}

@MainActor func testAnyLostPermissionSendsTheNextStepsBack() async {
    for step in [WelcomeStep.holdKey, .microphone] {
        for lost in WelcomePermission.allCases {
            let devices = FakeWelcomeDevices(granted: Set(WelcomePermission.allCases))
            let welcome = model(devices)
            welcome.jump(to: .permissions)
            await welcome.refresh()
            welcome.jump(to: step)
            devices.revoke(lost)
            await welcome.refresh()
            expectEq(welcome.flow.step, .permissions, "\(step) sin \(lost): vuelve a permisos")
        }
    }
}

@MainActor func testThePollNeverSpendsTheSecondAsk() async {
    let devices = FakeWelcomeDevices(granted: [.screenRecording])
    devices.captures = false
    let welcome = relaunchedOnPermissions(devices)
    await welcome.refresh()
    await welcome.refresh()
    await welcome.refresh()
    expect(devices.requests.isEmpty, "el sondeo nunca pide")
    await welcome.refocused()
    expectEq(devices.requests, [.screenRecording], "el segundo pedido sigue armado para el foco")
}

@MainActor func testGoingBackToPermissionsDoesNotRearm() async {
    let devices = FakeWelcomeDevices(granted: Set(WelcomePermission.allCases))
    let welcome = relaunchedOnPermissions(devices)
    await welcome.refresh()
    welcome.next()
    expectEq(welcome.flow.step, .holdKey, "avanza")
    devices.revoke(.microphone)
    await welcome.refresh()
    expectEq(welcome.flow.step, .permissions, "vuelve a permisos")
    devices.captures = false
    await welcome.refocused()
    expect(devices.requests.isEmpty, "volver por un permiso perdido no es un relanzamiento")
}

@MainActor func testADenialAtThePromptLeavesTheRowOff() async {
    let devices = FakeWelcomeDevices()
    devices.denies = true
    let welcome = model(devices)
    welcome.jump(to: .permissions)
    await welcome.request(.screenRecording)
    expect(!welcome.facts.granted.contains(.screenRecording), "negado: la fila sigue apagada")
    expect(!welcome.screenRecordingUnverified, "negado: no es encendido sin funcionar")
    expectEq(devices.verifies, 0, "negado: sin permiso no hay sondeo")
}

@MainActor func testTwoRefocusesAtOnceAskOnce() async {
    let devices = FakeWelcomeDevices(granted: [.screenRecording])
    devices.captures = false
    let welcome = relaunchedOnPermissions(devices)
    async let first: Void = welcome.refocused()
    async let second: Void = welcome.refocused()
    _ = await (first, second)
    expectEq(devices.requests.count, 1, "el paso y el foco juntos piden una sola vez")
}
