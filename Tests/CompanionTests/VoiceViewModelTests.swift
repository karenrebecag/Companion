import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func voiceViewModelTests() async {
    await testVoiceCopy()
    await testVoiceViewModelIdleAtInit()
    await testVoiceViewModelForwardsControls()
    await testVoiceViewModelOnAppearMirrorsSnapshotAndLevels()
    await testVoiceViewModelIsActivePerState()
    await testVoiceViewModelClassicFallbackStatus()
    await testVoiceViewModelIdleClearsStatus()
    await testVoiceViewModelToggleMuteForwards()
    await testVoiceViewModelOnAppearIsIdempotent()
    await testVoiceViewModelDoubleStartAndHangUp()
}

@MainActor func testVoiceCopy() async {
    expectEq(
        VoiceCopy.fallbackClassic,
        "La voz en vivo no está disponible. Sigo por el micrófono clásico.",
        "copy: fallback clásico")
    expectEq(
        VoiceCopy.functionRefusal,
        "Los encargos estarán disponibles en una próxima versión.",
        "copy: function refusal al estilo handoff")
    expectEq(
        VoiceCopy.failure(.micDenied),
        "Sin permiso de micrófono. Revisa Ajustes del sistema.",
        "copy: micDenied")
    expectEq(
        VoiceCopy.failure(.micUnavailable),
        "El micrófono no está disponible.",
        "copy: micUnavailable")
    expectEq(
        VoiceCopy.failure(.micSilent),
        "El micrófono no entregó audio.",
        "copy: micSilent")
    expectEq(
        VoiceCopy.failure(.notHeard),
        "No te escuché.",
        "copy: notHeard")
    expectEq(
        VoiceCopy.failure(.speechEngine),
        "Me quedé sin voz. Revisa el TTS.",
        "copy: speechEngine")
    expectEq(
        VoiceCopy.failure(.noProviders),
        "No hay un proveedor de voz disponible.",
        "copy: noProviders")
    expectEq(
        VoiceCopy.failure(.sessionDropped),
        "La sesión de voz se cayó.",
        "copy: sessionDropped")

    let all: [TurnFailure] = [
        .micDenied, .micUnavailable, .micSilent, .notHeard,
        .speechEngine, .noProviders, .sessionDropped,
    ]
    var seen: Set<String> = []
    for reason in all {
        let text = VoiceCopy.failure(reason)
        expect(!text.isEmpty, "copy: \(reason) no vacío")
        expect(seen.insert(text).inserted, "copy: \(reason) distinto")
    }
}

@MainActor func testVoiceViewModelIdleAtInit() async {
    let voice = RecordingVoice()
    let thread = FakePresenter()
    let vm = VoiceViewModel(voice: voice, thread: thread)
    expectEq(vm.snapshot, .idle, "init: snapshot idle")
    expectEq(vm.levels, VoiceLevels(mic: 0, agent: 0), "init: levels cero")
    expect(vm.statusText == nil, "init: sin status")
    expect(!vm.isActive, "init: idle no está activo")
    expectEq(voice.started, 0, "init: no arranca solo")
}

@MainActor func testVoiceViewModelForwardsControls() async {
    let voice = RecordingVoice()
    let vm = VoiceViewModel(voice: voice, thread: FakePresenter())
    vm.start()
    await pumpUntil("fwd: start") { voice.started == 1 }
    vm.advance()
    await pumpUntil("fwd: advance") { voice.advanced == 1 }
    vm.hangUp()
    await pumpUntil("fwd: hangUp") { voice.hungUp == 1 }
    expectEq(voice.started, 1, "fwd: un start")
    expectEq(voice.advanced, 1, "fwd: un advance")
    expectEq(voice.hungUp, 1, "fwd: un hangUp")
    expectEq(voice.muteToggles, 0, "fwd: mute no se toca")
}

@MainActor func testVoiceViewModelOnAppearMirrorsSnapshotAndLevels() async {
    let voice = RecordingVoice()
    let vm = VoiceViewModel(voice: voice, thread: FakePresenter())
    vm.onAppear()
    let snap = TurnSnapshot(state: .listening, pipeline: .realtime, muted: true)
    let levels = VoiceLevels(mic: 0.25, agent: -1)
    voice.yieldSnapshot(snap)
    voice.yieldLevels(levels)
    await pumpUntil("appear: snapshot") { vm.snapshot == snap }
    await pumpUntil("appear: levels") { vm.levels == levels }
    expect(vm.isActive, "appear: listening está activo")
    expect(vm.snapshot.muted, "appear: muted viaja")
    expectEq(vm.levels.mic, 0.25, "appear: mic fracción")
    expectEq(vm.levels.agent, -1, "appear: agent negativo")

    let unicode = TurnSnapshot(state: .speaking, pipeline: .classic)
    voice.yieldSnapshot(unicode)
    voice.yieldLevels(VoiceLevels(mic: 99, agent: 0))
    await pumpUntil("appear: speaking") { vm.snapshot.state == .speaking }
    expectEq(vm.snapshot.pipeline, .classic, "appear: pipeline clásico")
    expectEq(vm.levels.mic, 99, "appear: mic grande")
    voice.finish()
}

@MainActor func testVoiceViewModelIsActivePerState() async {
    let voice = RecordingVoice()
    let vm = VoiceViewModel(voice: voice, thread: FakePresenter())
    vm.onAppear()

    let active: [TurnState] = [.connecting, .listening, .thinking, .speaking]
    for state in active {
        voice.yieldSnapshot(TurnSnapshot(state: state))
        await pumpUntil("active: \(state)") { vm.snapshot.state == state && vm.isActive }
    }

    voice.yieldSnapshot(TurnSnapshot(state: .idle))
    await pumpUntil("active: idle") { vm.snapshot.state == .idle && !vm.isActive }
    voice.yieldSnapshot(TurnSnapshot(state: .error))
    await pumpUntil("active: error") { vm.snapshot.state == .error && !vm.isActive }
    voice.finish()
}

@MainActor func testVoiceViewModelClassicFallbackStatus() async {
    let voice = RecordingVoice()
    let thread = FakePresenter()
    let vm = VoiceViewModel(voice: voice, thread: thread)
    vm.onAppear()
    voice.yieldSnapshot(TurnSnapshot(state: .connecting, pipeline: .realtime))
    await pumpUntil("fallback: connecting") { vm.snapshot.state == .connecting }
    expect(vm.statusText == nil, "fallback: connecting no avisa clásico")

    voice.yieldSnapshot(TurnSnapshot(state: .listening, pipeline: .classic))
    await pumpUntil("fallback: status") {
        vm.statusText == VoiceCopy.fallbackClassic && thread.status == [VoiceCopy.fallbackClassic]
    }
    expectEq(vm.snapshot.pipeline, .classic, "fallback: pipeline clásico")
    expect(vm.isActive, "fallback: listening sigue activo")

    voice.yieldSnapshot(TurnSnapshot(state: .thinking, pipeline: .classic))
    await pumpUntil("fallback: thinking") { vm.snapshot.state == .thinking }
    expectEq(thread.status.count, 1, "fallback: no re-anuncia el mismo clásico")
    expectEq(vm.statusText, VoiceCopy.fallbackClassic, "fallback: status se queda")
    voice.finish()
}

@MainActor func testVoiceViewModelIdleClearsStatus() async {
    let voice = RecordingVoice()
    let thread = FakePresenter()
    let vm = VoiceViewModel(voice: voice, thread: thread)
    vm.onAppear()
    voice.yieldSnapshot(TurnSnapshot(state: .connecting, pipeline: .realtime))
    await pumpUntil("clear: realtime") { vm.snapshot.pipeline == .realtime }
    voice.yieldSnapshot(TurnSnapshot(state: .listening, pipeline: .classic))
    await pumpUntil("clear: fallback") { vm.statusText == VoiceCopy.fallbackClassic }
    voice.yieldSnapshot(.idle)
    await pumpUntil("clear: idle") { vm.snapshot == .idle && vm.statusText == nil }
    expect(thread.status == [VoiceCopy.fallbackClassic],
           "clear: el hilo conserva la nota persistida")
    voice.finish()
}

@MainActor func testVoiceViewModelToggleMuteForwards() async {
    let voice = RecordingVoice()
    let vm = VoiceViewModel(voice: voice, thread: FakePresenter())
    vm.onAppear()
    vm.toggleMute()
    await pumpUntil("mute: primer toggle") { voice.muteToggles == 1 && voice.muted }
    vm.toggleMute()
    await pumpUntil("mute: segundo toggle") { voice.muteToggles == 2 && !voice.muted }
    voice.yieldSnapshot(TurnSnapshot(state: .listening, pipeline: .realtime, muted: true))
    await pumpUntil("mute: snapshot") { vm.snapshot.muted }
    expect(vm.isActive, "mute: listening muted sigue activo")
    voice.finish()
}

@MainActor func testVoiceViewModelOnAppearIsIdempotent() async {
    let voice = RecordingVoice()
    let vm = VoiceViewModel(voice: voice, thread: FakePresenter())
    vm.onAppear()
    vm.onAppear()
    voice.yieldSnapshot(TurnSnapshot(state: .connecting, pipeline: .realtime))
    await pumpUntil("idem: connecting") { vm.snapshot.state == .connecting }
    expect(vm.isActive, "idem: connecting está activo")
    voice.finish()
}

@MainActor func testVoiceViewModelDoubleStartAndHangUp() async {
    let voice = RecordingVoice()
    let vm = VoiceViewModel(voice: voice, thread: FakePresenter())
    vm.start()
    vm.start()
    await pumpUntil("race: dos start") { voice.started == 2 }
    vm.hangUp()
    vm.hangUp()
    await pumpUntil("race: dos hangUp") { voice.hungUp == 2 }
    expectEq(voice.started, 2, "race: ambos start llegan")
    expectEq(voice.hungUp, 2, "race: ambos hangUp llegan")
}

final class RecordingVoice: VoiceControlling, @unchecked Sendable {
    private(set) var speeds: [Double] = []
    func setSpeed(_ speed: Double) async { speeds.append(speed) }
    func setVolume(_ volume: Double) async {}

    var started = 0, advanced = 0, hungUp = 0, muteToggles = 0
    var muted = false
    private let snapBox = StreamBox<TurnSnapshot>()
    private let levelBox = StreamBox<VoiceLevels>()
    var snapshots: AsyncStream<TurnSnapshot> { snapBox.stream }
    var levels: AsyncStream<VoiceLevels> { levelBox.stream }

    func start() async { started += 1 }
    func advance() async { advanced += 1 }
    func hangUp() async { hungUp += 1 }
    func toggleMute() async { muteToggles += 1; muted.toggle() }
    func push(attachment: AttachmentRef) async { pushed.append(attachment) }
    var pushed: [AttachmentRef] = []
    func yieldSnapshot(_ snapshot: TurnSnapshot) { snapBox.yield(snapshot) }
    func yieldLevels(_ value: VoiceLevels) { levelBox.yield(value) }
    func finish() { snapBox.finish(); levelBox.finish() }
}

// MARK: - Capacidad de interrupcion adaptativa (peticion de Karen, 6c)

@Test @MainActor func interruptCapabilityTests() async {
    testCapabilityDecision()
    await testRouteChangesFlipCapability()
}

@MainActor func testCapabilityDecision() {
    expectEq(InterruptCapability.decide(echoFreeOutput: true, aecActive: false),
             .voiceAndTap, "capacidad: audífonos ⇒ hablar encima")
    expectEq(InterruptCapability.decide(echoFreeOutput: false, aecActive: true),
             .voiceAndTap, "capacidad: AEC vivo ⇒ hablar encima")
    expectEq(InterruptCapability.decide(echoFreeOutput: false, aecActive: false),
             .tapOnly, "capacidad: bocinas sin AEC ⇒ solo el tap")
}

@MainActor func testRouteChangesFlipCapability() async {
    let route = ScriptedRoute()
    let vm = VoiceViewModel(
        voice: RecordingVoice(), thread: FakePresenter(), outputRoute: route)
    vm.onAppear()
    route.yield(false)
    await pumpUntil("ruta: bocinas ⇒ botón") {
        vm.interruptCapability == .tapOnly && !vm.echoFreeOutput
    }
    route.yield(true)
    await pumpUntil("ruta: conectar audífonos ⇒ flujo limpio") {
        vm.interruptCapability == .voiceAndTap && vm.echoFreeOutput
    }
    route.yield(false)
    await pumpUntil("ruta: desconectar ⇒ vuelve el botón") {
        vm.interruptCapability == .tapOnly
    }
}

private final class ScriptedRoute: OutputRouteObserving, @unchecked Sendable {
    private let box: (stream: AsyncStream<Bool>, continuation: AsyncStream<Bool>.Continuation)
    init() { box = AsyncStream.makeStream(of: Bool.self) }
    var echoFreeUpdates: AsyncStream<Bool> { box.stream }
    func yield(_ value: Bool) { box.continuation.yield(value) }
}
