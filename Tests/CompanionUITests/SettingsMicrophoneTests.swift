import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing
@testable import CompanionUI

// brief ajustes-hoja-incredible E35: the microphone popup lists the inputs,
// saves the pick, and listens through the chosen one while it is open.

private let mac = MicInput(id: "mac", name: "Mac", builtIn: true)
private let usb = MicInput(id: "usb", name: "USB Mic", builtIn: false)
private let both = MicDeviceSnapshot(devices: [mac, usb], systemDefaultName: "Mac")
private let macOnly = MicDeviceSnapshot(devices: [mac], systemDefaultName: "Mac")

private struct Rig {
    let model: SettingsMicrophoneModel
    let port: FakeMicPort
    let meter: FakeMicMeter
    let store: SpyMicStore
}

@MainActor private func rig(
    _ preference: MicPreference = .builtIn,
    snapshot: MicDeviceSnapshot = both,
    authorized: Bool = true,
    holdStarts: Bool = false,
    faults: [MicProbeFault?] = []
) -> Rig {
    let port = FakeMicPort(snapshot)
    let meter = FakeMicMeter(holdStarts: holdStarts)
    for fault in faults { meter.script(fault) }
    let store = SpyMicStore(preference)
    let model = SettingsMicrophoneModel(
        port: port, meter: meter, store: store,
        authorized: { authorized }, quietDelay: .milliseconds(40))
    return Rig(model: model, port: port, meter: meter, store: store)
}

@MainActor private func row(_ model: SettingsMicrophoneModel, _ id: String) -> MicMenuRow {
    guard let found = model.resolved.rows.first(where: { $0.id == id }) else {
        Issue.record("sin fila \(id)")
        return .builtIn(selected: false)
    }
    return found
}

@Suite @MainActor struct SettingsMicrophoneTests {
    @Test func choosingARowSavesItAndTheCurrentOrMissingRowDoesNot() async {
        await pinLanguage {
            let rig = rig(.device(id: "gone", name: "AirPods"))
            rig.model.opened()
            rig.model.choose(row(rig.model, "absent-gone"))
            expectEq(rig.store.saves, [], "elegir: la fila ausente no guarda")
            rig.model.choose(row(rig.model, "input-usb"))
            expectEq(rig.store.saves, [.device(id: "usb", name: "USB Mic")], "elegir: un dispositivo se guarda")
            rig.model.choose(row(rig.model, "input-usb"))
            expectEq(rig.store.saves.count, 1, "elegir: la fila actual no vuelve a guardar")
            rig.model.choose(row(rig.model, "built-in"))
            expectEq(rig.store.saves.last, .builtIn, "elegir: el integrado se guarda como integrado")
            rig.model.closed()
        }
    }

    @Test func openingListensOnlyWhenTheMicIsAlreadyAllowed() async {
        await pinLanguage {
            let allowed = rig()
            allowed.model.opened()
            allowed.model.opened()
            await pumpUntil("abrir: arranca el medidor") { allowed.meter.starts.count >= 1 }
            await settle()
            expectEq(allowed.meter.starts, [.device("mac")], "abrir: una vez, hacia el micrófono resuelto")
            allowed.model.closed()

            let blocked = rig(authorized: false)
            blocked.model.opened()
            await settle()
            expectEq(blocked.meter.starts, [], "abrir sin permiso: no se pide ni se escucha")
            expect(!blocked.model.testing, "abrir sin permiso: no queda midiendo")
            expectEq(blocked.port.watcherCount, 1, "abrir sin permiso: la lista sí se sigue")
            blocked.model.closed()
        }
    }

    @Test func withoutAnInjectedCheckThePermissionComesFromTheMeter() async {
        await pinLanguage {
            let meter = FakeMicMeter(authorized: false)
            let model = SettingsMicrophoneModel(
                port: FakeMicPort(both), meter: meter, store: SpyMicStore(), quietDelay: .milliseconds(40))
            model.opened()
            await settle()
            expectEq(meter.starts, [], "permiso: el medidor dice que no, no se arranca")
            model.closed()
        }
    }

    @Test func closingStopsTheMeterAndTheWatch() async {
        await pinLanguage {
            let rig = rig()
            rig.model.opened()
            expectEq(rig.port.watcherCount, 1, "abrir: observa la lista")
            await pumpUntil("cerrar: hay medidor que parar") { !rig.meter.starts.isEmpty }
            rig.model.closed()
            expectEq(rig.meter.stops, 1, "cerrar: para el medidor")
            expectEq(rig.port.watcherCount, 0, "cerrar: deja de observar")
            expect(!rig.model.testing, "cerrar: ya no mide")
        }
    }

    @Test func theListIsLiveAndTheProbeRestartsOnlyWhenTheInputChanges() async {
        await pinLanguage {
            let rig = rig(.device(id: "usb", name: "USB Mic"))
            rig.model.opened()
            await pumpUntil("lista: primer arranque") { rig.meter.starts.count == 1 }
            let extra = MicInput(id: "z", name: "Zed", builtIn: false)
            rig.port.publish(MicDeviceSnapshot(devices: [mac, usb, extra], systemDefaultName: "Mac"))
            await pumpUntil("lista: el nuevo aparece") {
                rig.model.resolved.rows.contains { $0.id == "input-z" }
            }
            expectEq(rig.meter.starts, [.device("usb")], "lista: un dispositivo ajeno no reinicia la prueba")
            rig.port.publish(macOnly)
            await pumpUntil("lista: el elegido se fue") { rig.meter.starts.count == 2 }
            expectEq(rig.meter.starts.last, .systemDefault, "lista: sigue al del sistema")
            expect(rig.model.resolved.rows.contains { $0.id == "absent-usb" }, "lista: la fila ausente aparece")
            rig.model.closed()
        }
    }

    @Test func aFaultShowsItsNoticeAndTryAgainRestartsTheProbe() async {
        await pinLanguage {
            let rig = rig(faults: [.blocked])
            rig.model.opened()
            await pumpUntil("falla: aviso") { rig.model.noticeText != nil }
            expectEq(rig.model.noticeText, Localized.string("settings.microphone.blocked"), "falla: el aviso")
            expect(rig.model.canRetry, "falla: se ofrece Try again")
            expect(!rig.model.testing, "falla: ya no mide")
            rig.model.retry()
            expectEq(rig.model.noticeText, nil, "reintentar: el aviso se va")
            expect(!rig.model.canRetry, "reintentar: sin falla no hay botón")
            await pumpUntil("reintentar: arranca de nuevo") { rig.meter.starts.count == 2 }
            rig.model.closed()
        }
    }

    @Test func pickingAnotherRowAfterAFaultRestartsTowardItAndClearsTheNotice() async {
        await pinLanguage {
            let rig = rig(faults: [.noInput])
            rig.model.opened()
            await pumpUntil("falla: aviso") { rig.model.noticeText != nil }
            rig.model.choose(row(rig.model, "input-usb"))
            expectEq(rig.model.noticeText, nil, "elegir tras una falla: el aviso se va")
            await pumpUntil("elegir tras una falla: reintenta") { rig.meter.starts.count == 2 }
            expectEq(rig.meter.starts.last, .device("usb"), "elegir tras una falla: hacia la nueva elección")
            rig.model.closed()
        }
    }

    @Test func aListChangeAfterAFaultRestartsTowardTheSystemDefault() async {
        await pinLanguage {
            let rig = rig(.device(id: "usb", name: "USB Mic"), faults: [.failed])
            rig.model.opened()
            await pumpUntil("falla: aviso") { rig.model.noticeText != nil }
            rig.port.publish(macOnly)
            await pumpUntil("cambio de lista: reintenta") { rig.meter.starts.count == 2 }
            expectEq(rig.meter.starts.last, .systemDefault, "cambio de lista tras una falla: el del sistema")
            rig.model.closed()
        }
    }

    @Test func aFailedSaveKeepsTheChoiceAndSaysSo() async {
        await pinLanguage {
            let rig = rig()
            rig.model.opened()
            await pumpUntil("guardar: midiendo") { rig.meter.starts.count == 1 }
            rig.store.failNextSave()
            rig.model.choose(row(rig.model, "input-usb"))
            expectEq(rig.model.preference, .builtIn, "guardar falló: la preferencia no cambia")
            expect(row(rig.model, "built-in").selected, "guardar falló: la fila elegida sigue siendo la misma")
            expectEq(rig.model.noticeText, Localized.string("settings.microphone.saveFailed"), "guardar falló: lo dice")
            expect(!rig.model.canRetry, "guardar falló: no es una falla de la prueba")
            expectEq(rig.meter.starts.count, 1, "guardar falló: la prueba sigue donde estaba")
            rig.model.choose(row(rig.model, "input-usb"))
            expectEq(rig.model.noticeText, nil, "guardar bien después: el aviso se va")
            expectEq(rig.model.preference, .device(id: "usb", name: "USB Mic"), "guardar bien después: cambia")
            rig.model.closed()
        }
    }

    @Test func quietAfterTheDelayAndALaterLevelClearsIt() async {
        await pinLanguage {
            let rig = rig()
            rig.model.opened()
            await pumpUntil("silencio: aviso") { rig.model.noticeText != nil }
            expectEq(rig.model.noticeText, Localized.string("settings.microphone.quiet"), "silencio: el aviso")
            expect(!rig.model.canRetry, "silencio: no es una falla, sin botón")
            rig.model.heard(0.5)
            expectEq(rig.model.noticeText, nil, "silencio: un nivel posterior lo quita")
            rig.model.closed()
        }
    }

    @Test func aProbeOvertakenByAChoiceDoesNotStopTheNewOne() async {
        await pinLanguage {
            let rig = rig(holdStarts: true)
            rig.model.opened()
            await pumpUntil("carrera: primer arranque en vuelo") { rig.meter.starts.count == 1 }
            rig.model.choose(row(rig.model, "input-usb"))
            await pumpUntil("carrera: segundo arranque en vuelo") { rig.meter.starts.count == 2 }
            rig.meter.release(0)
            await settle()
            expectEq(rig.meter.stops, 0, "carrera: el arranque superado no para el medidor compartido")
            rig.meter.release(1)
            await settle()
            expectEq(rig.meter.stops, 0, "carrera: el vigente sigue midiendo")
            expectEq(rig.meter.starts, [.device("mac"), .device("usb")], "carrera: hacia cada elección")
            rig.model.closed()
        }
    }

    @Test func theBarsSmoothTheLevelLikeTheReference() async {
        await pinLanguage {
            let rig = rig()
            rig.model.opened()
            await pumpUntil("barras: midiendo") { rig.model.testing }
            await pumpUntil("barras: arrancó") { !rig.meter.starts.isEmpty }
            expectEq(rig.model.litBars, 0, "barras: sin nivel, apagadas")
            rig.model.heard(1)
            expectEq(rig.model.litBars, 4, "barras: 0.6 de un nivel lleno son 4 de 6")
            rig.model.heard(1)
            expectEq(rig.model.litBars, 5, "barras: 0.4 del anterior más 0.6 del nuevo son 5 de 6")
            rig.model.heard(0)
            expectEq(rig.model.litBars, 2, "barras: baja suave, no de golpe")
            rig.model.closed()
        }
    }

    @Test func theRowShowsTheCurrentDeviceNameAndTheReferenceWording() async {
        await pinLanguage {
            let renamed = rig(.device(id: "usb", name: "Old name"))
            expectEq(renamed.model.rowSubtitle, "USB Mic", "fila: el nombre vigente, no el guardado")
            expectEq(rig(.builtIn).model.rowSubtitle, "Built-in mic", "fila: integrado")
            expectEq(rig(.systemDefault).model.rowSubtitle, "Auto-detect — your computer's default",
                     "fila: el del sistema")
            let gone = rig(.device(id: "gone", name: "AirPods"), snapshot: macOnly)
            expectEq(gone.model.rowSubtitle, "Auto-detect (Mac) — AirPods isn't connected", "fila: ausente")
        }
    }

    @Test func theCardsUseTheReferenceCopy() async {
        await pinLanguage {
            expectEq(MicRowCopy.title(.systemDefault(name: "Mac", holding: false, selected: false)),
                     "Auto-detect (Mac)", "tarjeta: sistema con nombre")
            expectEq(MicRowCopy.title(.systemDefault(name: nil, holding: false, selected: false)),
                     "Auto-detect", "tarjeta: sistema sin nombre")
            expectEq(MicRowCopy.title(.builtIn(selected: true)), "Built-in mic", "tarjeta: integrado")
            expectEq(MicRowCopy.subtitle(.builtIn(selected: true)), "Even with AirPods in.", "tarjeta: sub integrado")
            expectEq(MicRowCopy.subtitle(.systemDefault(name: nil, holding: true, selected: true)),
                     "In use until your picked mic is back.", "tarjeta: sistema en espera")
            expectEq(MicRowCopy.subtitle(.systemDefault(name: nil, holding: false, selected: true)),
                     "Follows your computer’s setting.", "tarjeta: sistema")
            expectEq(MicRowCopy.subtitle(.missing(id: "x", name: "X")),
                     "Plug it back in and Companion switches to it again.", "tarjeta: ausente")
            expectEq(Localized.string("settings.microphone.popup"),
                     "Which one Companion listens through. Pick one and speak.", "popup: subtítulo")
        }
    }
}
