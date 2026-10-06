import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func saveNoticeHidesOnTheFirstTimerWhenTwoSavesOverlap() {
    let center = SettingsSaveCenter()
    let t0 = Date(timeIntervalSinceReferenceDate: 10_000)
    let first = center.record(.name, at: t0)
    let second = center.record(.profile, at: t0.addingTimeInterval(0.4))
    expect(first != nil && second != nil, "ambos guardados programan un plazo")
    guard let first, let second else { return }
    expect(center.notice.visible, "el aviso esta visible")
    expect(first < second, "el primer plazo vence antes")
    center.fire(deadline: first)
    expect(!center.notice.visible, "el primer plazo apaga el aviso")
    expectEq(center.notice.deadlines, [second], "el segundo plazo sigue vivo")
}

@Test @MainActor func saveNoticeALaterDeadlineFiringAfterHiddenStaysHidden() {
    let center = SettingsSaveCenter()
    let t0 = Date(timeIntervalSinceReferenceDate: 10_000)
    guard let first = center.record(.name, at: t0),
          let second = center.record(.profile, at: t0.addingTimeInterval(0.4))
    else { return expect(false, "ambos guardados programan un plazo") }
    center.fire(deadline: first)
    center.fire(deadline: second)
    expect(!center.notice.visible, "el plazo tardio no lo vuelve a mostrar")
    expect(center.notice.deadlines.isEmpty, "no quedan plazos")
}

@Test @MainActor func saveNoticeAStaleDeadlineStillHidesALaterShow() {
    let center = SettingsSaveCenter()
    let t0 = Date(timeIntervalSinceReferenceDate: 10_000)
    guard let first = center.record(.name, at: t0),
          let second = center.record(.profile, at: t0.addingTimeInterval(0.4))
    else { return expect(false, "ambos guardados programan un plazo") }
    center.fire(deadline: first)
    let again = center.record(.voice, at: first.addingTimeInterval(0.1))
    expect(center.notice.visible, "un guardado posterior vuelve a mostrarse")
    center.fire(deadline: second)
    expect(!center.notice.visible, "KD4: el plazo que quedo pendiente tambien apaga")
    expectEq(center.notice.deadlines, [again].compactMap { $0 }, "el plazo nuevo sigue anotado")
}

@Test @MainActor func saveNoticeAnnouncesNameProfileMicLoginVolumeDiagnosticsAndVoice() {
    let now = Date(timeIntervalSinceReferenceDate: 0)
    let kinds: [SettingsSaveKind] = [
        .name, .profile, .microphone, .launchAtLogin, .volume, .diagnostics, .voice,
    ]
    for kind in kinds {
        let center = SettingsSaveCenter()
        let deadline = center.record(kind, at: now)
        expectEq(
            deadline, now.addingTimeInterval(SettingsSaveNotice.duration),
            "\(kind) avisa")
        expect(center.notice.visible, "\(kind) queda visible")
    }
}

@Test @MainActor func saveNoticeStaysQuietForMuteModelWakeAndPassiveMode() {
    let center = SettingsSaveCenter()
    let now = Date(timeIntervalSinceReferenceDate: 0)
    let kinds: [SettingsSaveKind] = [
        .muteVoice, .muteSystemSounds, .muteWhileTalking, .modelTier, .wakeWord, .passive,
    ]
    for kind in kinds {
        expect(center.record(kind, at: now) == nil, "\(kind) no avisa")
        expect(!center.notice.visible, "\(kind) no lo muestra")
    }
    expect(center.notice.deadlines.isEmpty, "el grupo callado no deja plazos")
}

@Test @MainActor func saveNoticeFailedSetterRevertsAndKeepsTheInlineError() async {
    await Localized.scoped(to: .en) {
        var slot = SettingsSaveSlot(committed: "Ada")
        let token = slot.begin("Bea")
        expect(slot.saving, "mientras corre")
        expectEq(slot.shown, "Bea", "el valor nuevo se ve ya")
        expect(slot.fail(token), "el fallo de esta generacion cuenta")
        expectEq(slot.shown, "Ada", "vuelve al anterior")
        expectEq(slot.committed, "Ada", "lo ya guardado no cambia")
        expect(!slot.saving, "ya no esta guardando")
        expectEq(slot.error, SettingsSaveCopy.failed, "el error de la fila")
        expectEq(
            SettingsSaveRow.subtitle(error: slot.error, description: "City for nearby"),
            SettingsSaveCopy.failed,
            "la fila muestra el error y no la descripcion")
        expectEq(
            SettingsSaveRow.subtitle(error: nil, description: "City for nearby"),
            "City for nearby",
            "sin error queda la descripcion")
        expectEq(
            SettingsSaveRow.subtitle(error: "", description: "City for nearby"),
            "City for nearby",
            "un error vacio no tapa la descripcion")
    }
}

@Test @MainActor func saveNoticeStaleFailureLeavesTheNewerEdit() {
    var slot = SettingsSaveSlot(committed: "Ada")
    let first = slot.begin("Bea")
    let second = slot.begin("Cia")
    expect(!slot.fail(first), "un fallo viejo no cuenta")
    expectEq(slot.shown, "Cia", "el edit nuevo sigue en pantalla")
    expect(slot.saving, "el edit nuevo sigue en curso")
    expect(slot.error == nil, "no pinta el error del intento viejo")
    expect(!slot.succeed(first), "un exito viejo tampoco cuenta")
    expect(slot.succeed(second), "el edit nuevo si cierra")
    expectEq(slot.committed, "Cia", "queda el edit nuevo")
    expect(!slot.saving, "el cierre apaga el estado de guardado")
}

@Test @MainActor func saveNoticeUsesTheReferenceDurationNoAnimationAndAPopupShadow() {
    expectEq(
        SettingsSaveNotice.duration, 1.2,
        "local reference; brief ajustes-hoja-incredible S3")
    expectEq(SettingsSaveNotice.animates, false, "sin animacion")
    expectEq(SettingsSaveNotice.radius, Radius.chip, "radio de chip")
    expectEq(SettingsSaveNotice.elevation, Elevation.popover, "sombra de popup")
}

@Test @MainActor func saveNoticeCopyIsLocalized() async {
    await Localized.scoped(to: .en) {
        expectEq(SettingsSaveCopy.saved, "Saved", "aviso en ingles")
        expectEq(
            SettingsSaveCopy.failed,
            "That did not save. The previous value is back. Try again.",
            "error en ingles")
    }
    await Localized.scoped(to: .es) {
        expectEq(SettingsSaveCopy.saved, "Guardado", "aviso en espanol")
        expectEq(
            SettingsSaveCopy.failed,
            "No se guardó. Quedó el valor anterior. Inténtalo de nuevo.",
            "error en espanol")
    }
}

// MARK: - Save step, announcements and timer

private struct Boom: Error {}

/// Lets a test hold the sleeper until it decides the timer is due.
@MainActor private final class Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requested: [TimeInterval] = []

    func wait(_ seconds: TimeInterval) async {
        requested.append(seconds)
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        open = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor private final class Harness {
    let gate = Gate()
    var spoken: [String] = []
    let now = Date(timeIntervalSinceReferenceDate: 50_000)
    lazy var center = SettingsSaveCenter(
        now: { [now] in now },
        sleep: { [gate] seconds in await gate.wait(seconds) },
        announce: { [unowned self] in spoken.append($0) })
}

@Test @MainActor func saveStepFailingWriteRevertsSetsTheRowErrorAndRecordsNothing() {
    let h = Harness()
    defer { h.gate.release() }
    var slot = SettingsSaveSlot(committed: "Ada")
    h.center.commit(.name, &slot, next: "Bea") { _ in throw Boom() }
    expectEq(slot.shown, "Ada", "vuelve al valor anterior")
    expectEq(slot.committed, "Ada", "lo guardado no cambia")
    expectEq(slot.error, SettingsSaveCopy.failed, "el error de la fila")
    expect(!slot.saving, "ya no guarda")
    expect(!h.center.notice.visible, "un fallo no muestra el aviso")
    expect(h.center.notice.deadlines.isEmpty, "ni programa un plazo")
    expectEq(h.spoken, [SettingsSaveCopy.failed], "VoiceOver dice el fallo, no el guardado")
}

@Test @MainActor func saveStepSucceedingWriteRecordsTheNoticeOnce() {
    let h = Harness()
    defer { h.gate.release() }
    var slot = SettingsSaveSlot(committed: "Ada")
    var written: [String] = []
    h.center.commit(.name, &slot, next: "Bea") { written.append($0) }
    expectEq(written, ["Bea"], "el valor se persiste")
    expectEq(slot.committed, "Bea", "queda guardado")
    expect(slot.error == nil, "sin error")
    expectEq(h.center.notice.deadlines.count, 1, "un solo plazo")
    expect(h.center.notice.visible, "el aviso se ve")
}

@Test @MainActor func saveStepAnUnchangedValueDoesNotWrite() {
    let h = Harness()
    defer { h.gate.release() }
    var slot = SettingsSaveSlot(committed: "Ada")
    var writes = 0
    h.center.commit(.name, &slot, next: "Ada") { _ in writes += 1 }
    expectEq(writes, 0, "el mismo texto no escribe")
    expect(!h.center.notice.visible, "ni avisa")
}

@Test @MainActor func saveStepALateFailureOfAnOlderEditLeavesTheNewerOne() {
    let h = Harness()
    defer { h.gate.release() }
    var slot = SettingsSaveSlot(committed: "Ada")
    let a = slot.begin("Bea")
    let b = slot.begin("Cia")
    h.center.finish(.profile, &slot, b, .success(()))
    h.center.finish(.profile, &slot, a, .failure(Boom()))
    expectEq(slot.shown, "Cia", "se ve el edit B")
    expectEq(slot.committed, "Cia", "queda el edit B")
    expect(slot.error == nil, "el fallo viejo no pinta error")
    expectEq(h.center.notice.deadlines.count, 1, "un solo aviso")
    expectEq(h.spoken, [SettingsSaveCopy.saved], "solo se anuncia el guardado de B")
}

@Test @MainActor func editingAnnouncesOncePerEditNotPerKeystroke() {
    let h = Harness()
    defer { h.gate.release() }
    var slot = SettingsSaveSlot(committed: "")
    var written: [String] = []
    for text in ["B", "Be", "Bea", "Bea ", "Bea R"] {
        h.center.commit(.profile, &slot, next: text, timing: .onEndEditing) { written.append($0) }
    }
    expectEq(written.count, 5, "cada tecla se sigue persistiendo")
    expect(!h.center.notice.visible, "teclear solo no muestra el aviso")
    expect(h.center.notice.deadlines.isEmpty, "ni programa plazos")
    expect(h.spoken.isEmpty, "ni anuncia")
    h.center.endEditing(.profile, &slot)
    expectEq(h.center.notice.deadlines.count, 1, "al terminar, un plazo")
    expectEq(h.spoken, [SettingsSaveCopy.saved], "y un anuncio")
    h.center.endEditing(.profile, &slot)
    expectEq(h.center.notice.deadlines.count, 1, "terminar otra vez sin cambios no repite")
}

@Test @MainActor func failingKeystrokesAnnounceTheFailureOncePerEditingSession() {
    let h = Harness()
    defer { h.gate.release() }
    var slot = SettingsSaveSlot(committed: "")
    for text in ["B", "Be", "Bea"] {
        h.center.commit(.profile, &slot, next: text, timing: .onEndEditing) { _ in throw Boom() }
    }
    expectEq(h.spoken, [SettingsSaveCopy.failed], "tres fallos, un anuncio")
    expectEq(slot.error, SettingsSaveCopy.failed, "la fila sigue mostrando el error")
    h.center.endEditing(.profile, &slot)
    h.center.endEditing(.profile, &slot)
    expectEq(h.spoken, [SettingsSaveCopy.failed], "terminar la edicion dos veces no suma nada")
    h.center.commit(.profile, &slot, next: "C", timing: .onEndEditing) { _ in throw Boom() }
    expectEq(h.spoken, [SettingsSaveCopy.failed, SettingsSaveCopy.failed], "otra sesion anuncia de nuevo")
}

@Test @MainActor func endingAnEditThatNeverWroteStaysQuiet() {
    let h = Harness()
    defer { h.gate.release() }
    var slot = SettingsSaveSlot(committed: "Ada")
    h.center.endEditing(.name, &slot)
    expect(!h.center.notice.visible, "enfocar y salir no avisa")
}

@Test @MainActor func profileFieldsMapToTheirNoticeKindAndAnnounceThroughTheStep() {
    let kinds: [(SettingsProfileField, SettingsSaveKind)] = [
        (.name, .name), (.city, .profile), (.about, .profile), (.instructions, .profile),
    ]
    for (field, kind) in kinds {
        expectEq(field.kind, kind, "\(field) dispara \(kind)")
        let h = Harness()
        defer { h.gate.release() }
        var slot = SettingsSaveSlot(committed: "")
        h.center.commit(field.kind, &slot, next: "x") { _ in }
        expect(h.center.notice.visible, "\(field) muestra el aviso")
    }
}

@Test @MainActor func avatarResultMapsBothBranches() {
    let ok = SettingsAvatarResult(saved: true)
    expect(ok.error == nil, "guardado: sin error")
    expectEq(ok.notice, .profile, "guardado: avisa de perfil")
    let bad = SettingsAvatarResult(saved: false)
    expectEq(bad.error, SettingsSaveCopy.failed, "fallo: error localizado")
    expect(bad.notice == nil, "fallo: no avisa")
}

@Test @MainActor func avatarSetRecordsTheNoticeOnlyOnSuccess() {
    let h = Harness()
    defer { h.gate.release() }
    expectEq(h.center.avatarSet(saved: false), SettingsSaveCopy.failed, "fallo: texto de error")
    expect(!h.center.notice.visible, "fallo: sin aviso")
    expectEq(h.spoken, [SettingsSaveCopy.failed], "fallo: se anuncia")
    expect(h.center.avatarSet(saved: true) == nil, "exito: sin error")
    expect(h.center.notice.visible, "exito: aviso")
    expectEq(h.spoken, [SettingsSaveCopy.failed, SettingsSaveCopy.saved], "exito: se anuncia")
}

@Test @MainActor func voiceSettingsUnchangedWritesNothingAndRaisesNoNotice() {
    let h = Harness()
    defer { h.gate.release() }
    let base = VoiceSettings()
    var written: [VoiceSettings] = []
    let same = h.center.updateVoice(base, mutate: { $0.voice = base.voice }) { written.append($0) }
    expectEq(same, base, "devuelve lo mismo")
    expect(written.isEmpty, "el mismo valor no escribe")
    expect(!h.center.notice.visible, "ni avisa")
    expect(h.spoken.isEmpty, "ni anuncia")
}

@Test @MainActor func voiceSettingsChangeRecordsTheNoticeAndPersistsOnce() {
    let h = Harness()
    defer { h.gate.release() }
    let base = VoiceSettings()
    let other = VoiceID.allCases.first { $0 != base.voice } ?? base.voice
    var written: [VoiceSettings] = []
    let next = h.center.updateVoice(base, mutate: { $0.voice = other }) { written.append($0) }
    expectEq(next.voice, other, "devuelve la copia nueva")
    expectEq(written.map(\.voice), [other], "persiste la copia")
    expectEq(h.center.notice.deadlines.count, 1, "un aviso")
}

/// The real model writes the shared voice preference, which the integration
/// tests own; this drives the same decision through its seam instead.
@Test @MainActor func elevenLabsChoicesRecordTheNoticeOnlyWhenTheyStick() {
    let h = Harness()
    defer { h.gate.release() }
    var errorText: String? = nil
    h.center.settleVoiceChoice(apply: { errorText = "invalid id" }, errorText: { errorText })
    expect(!h.center.notice.visible, "un id invalido no avisa")
    expectEq(h.spoken, ["invalid id"], "el error del modelo se anuncia en vez del guardado")
    h.center.settleVoiceChoice(apply: { errorText = nil }, errorText: { errorText })
    expectEq(h.center.notice.deadlines.count, 1, "uno valido avisa y limpia el error")
    expectEq(h.spoken, ["invalid id", SettingsSaveCopy.saved], "el valido anuncia el guardado")
    h.center.settleVoiceChoice(apply: { errorText = "invalid id" }, errorText: { errorText })
    expectEq(h.center.notice.deadlines.count, 1, "otro invalido no suma otro aviso")
    expectEq(h.spoken.last, "invalid id", "y vuelve a anunciar el error")
}

@Test @MainActor func announcementsFollowTheNoticeAndQuietKindsSayNothing() async {
    await Localized.scoped(to: .en) {
        let h = Harness()
        defer { h.gate.release() }
        let task = h.center.saved(.name)
        expectEq(h.spoken, [SettingsSaveCopy.saved], "guardar nombre anuncia el texto una vez")
        let quiet = Harness()
        defer { quiet.gate.release() }
        for kind in [SettingsSaveKind.muteVoice, .muteSystemSounds, .muteWhileTalking, .modelTier, .wakeWord, .passive] {
            quiet.center.saved(kind)
        }
        expect(quiet.spoken.isEmpty, "los controles callados no anuncian")
    }
}

@Test @MainActor func savedSchedulesTheHideWithTheReturnedDeadlineAndTheInjectedSleepHidesIt() async {
    let h = Harness()
    defer { h.gate.release() }
    let task = h.center.saved(.name)
    expect(task != nil, "un guardado que avisa programa el plazo")
    expectEq(h.center.notice.deadlines, [h.now.addingTimeInterval(SettingsSaveNotice.duration)], "plazo = ahora + duracion")
    expect(h.center.notice.visible, "visible antes de que venza")
    h.gate.release()
    await task?.value
    expectEq(h.gate.requested.count, 1, "el sleeper se arma una vez")
    expect(
        abs((h.gate.requested.first ?? 0) - SettingsSaveNotice.duration) < 0.001,
        "la espera llega hasta el plazo")
    expect(!h.center.notice.visible, "al terminar la espera se oculta")
    expect(h.center.notice.deadlines.isEmpty, "y el plazo se consume")
}

@Test @MainActor func savedForAQuietKindSchedulesNothing() {
    let h = Harness()
    defer { h.gate.release() }
    expect(h.center.saved(.passive) == nil, "sin plazo no hay tarea")
    expect(h.gate.requested.isEmpty, "ni espera")
}
