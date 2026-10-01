import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Wave 12e. Dictar en el campo enfocado: la misma tecla, otro destino. El
// enrutador es puro; el ajuste persiste con el resto de la voz.

@Test @MainActor func dictationTests() {
    testTheRouterDecidesAtPress()
    testTheVoiceModePersists()
    testTheDictationKeyPersists()
    testDictationTapChangeDecision()
    testDictationKeyChangeNotifiesOnlyOnRealChange()
}

private func field(secure: Bool = false) -> FocusedField {
    FocusedField(app: "Slack", pid: 42, secure: secure)
}

/// 1. La tabla de §3.1: el modo, el campo enfocado y la confianza AX
/// deciden si soltar pega o envía.
@MainActor func testTheRouterDecidesAtPress() {
    let route = DictationRouter.destination
    expectEq(route(.agent, field(), true), .agent(nil), "ruta: agente es agente")
    expectEq(route(.agent, nil, false), .agent(nil), "ruta: agente sin campo ni confianza")

    expectEq(route(.dictation, field(), true), .dictation(field()), "ruta: dictar con campo pega")
    expectEq(route(.dictation, nil, true), .agent(.noField), "ruta: dictar sin campo cae al agente")
    expectEq(route(.dictation, field(secure: true), true), .agent(.noField),
             "ruta: una contraseña nunca es un campo")
    expectEq(route(.dictation, field(), false), .agent(.needsAccessibility),
             "ruta: dictar sin Accesibilidad avisa")

    expectEq(route(.automatic, field(), true), .dictation(field()), "ruta: automático con campo pega")
    expectEq(route(.automatic, nil, true), .agent(nil), "ruta: automático sin campo habla")
    expectEq(route(.automatic, field(secure: true), true), .agent(nil), "ruta: automático y contraseña habla")
    expectEq(route(.automatic, field(), false), .agent(nil),
             "ruta: automático sin Accesibilidad habla, sin avisar")
}

/// 10. `VoiceSettings.mode` nace en automático y persiste con el resto.
@MainActor func testTheVoiceModePersists() {
    expectEq(VoiceSettings().mode, .automatic, "modo: por defecto automático")
    expectEq(VoiceSettings.default.mode, .automatic, "modo: el default también")
    let before = VoiceProfile.settings
    defer { VoiceProfile.settings = before }
    var copy = before
    copy.mode = .dictation
    VoiceProfile.settings = copy
    expectEq(VoiceProfile.settings.mode, .dictation, "modo: vuelve de UserDefaults")
    copy.mode = .agent
    VoiceProfile.settings = copy
    expectEq(VoiceProfile.settings.mode, .agent, "modo: y cambia")
    expectEq(VoiceMode(rawValue: "nonsense"), nil, "modo: un valor extraño no es un modo")
}

/// 15b-2: `dictationKey` persists with the rest of the voice settings,
/// defaults to `.rightOption` (§11), and a stray stored value falls back to
/// it instead of crashing — same contract `mode` already had.
@MainActor func testTheDictationKeyPersists() {
    expectEq(VoiceSettings().dictationKey, .rightOption, "tecla: por defecto Opción derecha")
    expectEq(VoiceSettings.default.dictationKey, .rightOption, "tecla: el default también")
    let before = VoiceProfile.settings
    defer { VoiceProfile.settings = before }
    UserDefaults.standard.set("nonsense", forKey: "companion.voice.dictationKey")
    expectEq(VoiceProfile.settings.dictationKey, .rightOption, "tecla: un valor raro cae al default")
    var copy = before
    copy.dictationKey = .rightCommand
    VoiceProfile.settings = copy
    expectEq(VoiceProfile.settings.dictationKey, .rightCommand, "tecla: vuelve de UserDefaults")
    copy.dictationKey = .off
    VoiceProfile.settings = copy
    expectEq(VoiceProfile.settings.dictationKey, .off, "tecla: y se apaga")
    expectEq(DictationKey(rawValue: "nonsense"), nil, "tecla: un valor extraño no es una tecla")
}

/// Code review 2026-09-23 (medio): the App layer builds `dictationTap` once
/// at launch; nothing told it the setting later changed. This is the pure
/// rebuild decision it must act on — `.off` tears the tap down, any other
/// value rebuilds it with that key's own code and bit.
@MainActor func testDictationTapChangeDecision() {
    expectEq(DictationTapChange.decide(for: .off), .stop, "tap: apagar detiene")
    expectEq(DictationTapChange.decide(for: .rightOption), .rebuild(keyCode: 61, flag: 0x40),
             "tap: Opción derecha reconstruye con su código y bit")
    expectEq(DictationTapChange.decide(for: .rightCommand), .rebuild(keyCode: 54, flag: 0x10),
             "tap: Comando derecho reconstruye con el suyo")
}

/// The signal CompanionMain rebuilds on: `VoiceProfile.settings` is written
/// by every voice control (a volume drag fires many times a second), so the
/// notification must fire only when `dictationKey` itself actually changed —
/// not on every write of the other fields it travels with.
@MainActor func testDictationKeyChangeNotifiesOnlyOnRealChange() {
    let before = VoiceProfile.settings
    defer { VoiceProfile.settings = before }
    var copy = before
    copy.dictationKey = .rightOption
    VoiceProfile.settings = copy // known baseline, not asserted

    let counter = NotifyCounter()
    let observer = NotificationCenter.default.addObserver(
        forName: .companionDictationKeyDidChange, object: nil, queue: nil
    ) { _ in counter.increment() }
    defer { NotificationCenter.default.removeObserver(observer) }

    copy.speed = copy.speed == 1.0 ? 1.2 : 1.0
    VoiceProfile.settings = copy
    expectEq(counter.count, 0, "dictation notify: otro campo no avisa")

    copy.dictationKey = .rightCommand
    VoiceProfile.settings = copy
    expectEq(counter.count, 1, "dictation notify: cambiar la tecla sí avisa")

    VoiceProfile.settings = copy
    expectEq(counter.count, 1, "dictation notify: repetir el mismo valor no avisa de nuevo")
}

private final class NotifyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func increment() { lock.withLock { _count += 1 } }
}
