import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

@Test @MainActor func ambienceTests() {
    testCueTransitions()
    testObserverDrivesSound()
    testToggleSilencesNextThinking()
    testNoDoubleStart()
}

@MainActor func testCueTransitions() {
    expectEq(AmbienceCue.forTransition(from: .listening, to: .thinking), .start,
             "cue: entrar a thinking enciende")
    expectEq(AmbienceCue.forTransition(from: .thinking, to: .speaking), .stop,
             "cue: el agente habla, apaga")
    expectEq(AmbienceCue.forTransition(from: .thinking, to: .error), .stop,
             "cue: fallo apaga")
    expectEq(AmbienceCue.forTransition(from: .thinking, to: .idle), .stop,
             "cue: colgar apaga")
    expectEq(AmbienceCue.forTransition(from: .idle, to: .listening), .none,
             "cue: transiciones ajenas no tocan nada")
    expectEq(AmbienceCue.forTransition(from: .thinking, to: .thinking), .none,
             "cue: repetir estado no reinicia")
}

@MainActor func testObserverDrivesSound() {
    let sound = RecordingThinkingSound()
    let observer = AmbienceObserver(sound: sound, isEnabled: { true })
    for state in [TurnState.connecting, .listening, .thinking, .speaking] {
        observer.observe(state)
    }
    expectEq(sound.events, ["start", "stop"],
             "observer: un ciclo pensar ⇒ enciende y apaga una vez")
}

@MainActor func testToggleSilencesNextThinking() {
    let sound = RecordingThinkingSound()
    let gate = ToggleBox(false)
    let observer = AmbienceObserver(sound: sound, isEnabled: { gate.value })
    observer.observe(.listening)
    observer.observe(.thinking)
    expectEq(sound.events, [], "toggle: apagado ⇒ silencio")
    observer.observe(.listening)
    gate.value = true
    observer.observe(.thinking)
    expectEq(sound.events, ["start"],
             "toggle: encenderlo aplica al siguiente pensar, sin reiniciar nada")
}

@MainActor func testNoDoubleStart() {
    let sound = RecordingThinkingSound()
    let observer = AmbienceObserver(sound: sound, isEnabled: { true })
    observer.observe(.thinking)
    observer.observe(.thinking)
    observer.observe(.speaking)
    observer.observe(.speaking)
    expectEq(sound.events, ["start", "stop"],
             "observer: estados repetidos no duplican cues")
}

private final class RecordingThinkingSound: ThinkingSounding, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var events: [String] { lock.withLock { log } }
    func start() { lock.withLock { log.append("start") } }
    func stop() { lock.withLock { log.append("stop") } }
}

private final class ToggleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool
    init(_ value: Bool) { stored = value }
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
