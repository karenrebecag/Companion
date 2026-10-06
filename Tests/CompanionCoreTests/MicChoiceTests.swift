import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// brief ajustes-hoja-incredible E35
// The choice is an id the capture reads. A missing device follows the system
// default and stays stored, so it applies again when the device comes back.

private func suite() -> (String, UserDefaults) {
    let name = "MicChoiceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? UserDefaults.standard
    defaults.removePersistentDomain(forName: name)
    return (name, defaults)
}

@Test func aFakePortListsInputsAndReportsAChange() {
    let first = MicDeviceSnapshot(
        devices: [MicInput(id: "mac", name: "Mac", builtIn: true)],
        systemDefaultName: "Mac")
    let port = FakeMicPort(first)
    expectEq(port.snapshot().devices.map(\.id), ["mac"], "lista: el puerto entrega las entradas")
    let seen = LockedBox<[MicDeviceSnapshot]>([])
    let watch = port.watch { seen.value.append($0) }
    let second = MicDeviceSnapshot(devices: [
        MicInput(id: "z", name: "Zeta", builtIn: false),
        MicInput(id: "mac", name: "Mac", builtIn: true),
        MicInput(id: "a", name: "Alpha", builtIn: false),
    ], systemDefaultName: "Mac")
    port.publish(second)
    expectEq(seen.value.last?.devices.map(\.id), ["z", "mac", "a"], "lista: un cambio llega al observador")
    let rows = MicChoice.resolve(.device(id: "gone", name: "Gone"), second).rows
    expectEq(rows.map(\.id), ["built-in", "system", "input-z", "input-a", "absent-gone"],
             "lista: integrado, sistema, el resto en el orden del sistema, el ausente al final")
    watch.cancel()
    port.publish(first)
    expectEq(seen.value.count, 1, "lista: cancelar deja de avisar")
}

@Test func theChoiceSurvivesARelaunch() {
    let (name, defaults) = suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let store = MicPreferenceStore(defaults: defaults)
    expectEq(store.load(), .builtIn, "preferencia: sin clave, el del equipo")
    store.save(.device(id: "usb-1", name: "Blue"))
    let again = MicPreferenceStore(defaults: defaults)
    expectEq(again.load(), .device(id: "usb-1", name: "Blue"), "preferencia: sobrevive")
    store.save(.systemDefault)
    expectEq(again.load(), .systemDefault, "preferencia: el del sistema se lee")
    defaults.set(Data("no".utf8), forKey: MicPreferenceStore.key)
    expectEq(store.load(), .builtIn, "preferencia: basura vuelve al del equipo")
}

@Test func aMissingDeviceFallsBackToTheSystemDefault() {
    let (name, defaults) = suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let store = MicPreferenceStore(defaults: defaults)
    let saved = MicPreference.device(id: "gone", name: "AirPods")
    store.save(saved)
    let present = MicDeviceSnapshot(devices: [
        MicInput(id: "mac", name: "Mac", builtIn: true),
        MicInput(id: "usb", name: "USB", builtIn: false),
    ], systemDefaultName: "Mac")
    let resolved = MicChoice.resolve(store.load(), present)
    expectEq(resolved.captureID, nil, "ausente: la captura sigue al sistema")
    expectEq(resolved.missingName, "AirPods", "ausente: el nombre se conserva")
    expectEq(store.load(), saved, "ausente: la preferencia no se borra")
    let missing = resolved.rows.first { if case .missing = $0 { return true }; return false }
    expectEq(missing?.enabled, false, "ausente: la fila no se puede elegir")
    expectEq(missing?.selected, false, "ausente: no queda marcada")
    let system = resolved.rows.first { if case .systemDefault = $0 { return true }; return false }
    expectEq(system?.selected, true, "ausente: se usa el del sistema")
    if case .systemDefault(_, let holding, _) = system {
        expect(holding, "ausente: el del sistema avisa que es temporal")
    } else {
        expect(false, "ausente: hay fila de sistema")
    }
    let empty = MicChoice.resolve(saved, .empty)
    expectEq(empty.missingName, nil, "lista vacía: un id guardado no se da por ausente")
    expectEq(empty.captureID, nil, "lista vacía: la captura no inventa un id")
    expect(!empty.rows.contains { if case .missing = $0 { return true }; return false },
           "lista vacía: sin fila de ausente")
}

@Test func captureUsesTheChosenId() {
    let both = MicDeviceSnapshot(devices: [
        MicInput(id: "mac", name: "Mac", builtIn: true),
        MicInput(id: "mac-2", name: "Display", builtIn: true),
        MicInput(id: "usb", name: "USB", builtIn: false),
    ], systemDefaultName: "Mac")
    expectEq(MicChoice.captureID(preference: .device(id: "usb", name: "USB"), snapshot: both),
             "usb", "captura: el id elegido")
    expectEq(MicChoice.captureID(preference: .builtIn, snapshot: both),
             "mac", "captura: el primer integrado")
    expectEq(MicChoice.captureID(preference: .systemDefault, snapshot: both),
             nil, "captura: el sistema no fija un id")
    expectEq(MicChoice.captureID(preference: .device(id: "mac-2", name: "Display"), snapshot: both),
             "mac-2", "captura: un integrado guardado por id sigue siendo ese")
    let usbOnly = MicDeviceSnapshot(
        devices: [MicInput(id: "usb", name: "USB", builtIn: false)],
        systemDefaultName: "USB")
    expectEq(MicChoice.captureID(preference: .builtIn, snapshot: usbOnly),
             nil, "captura: sin integrado, el sistema")
    let fallen = MicChoice.resolve(.builtIn, usbOnly)
    expect(!fallen.rows.contains { if case .builtIn = $0 { return true }; return false },
           "sin integrado: no se ofrece esa fila")
    expect(fallen.rows.contains { if case .systemDefault(_, false, true) = $0 { return true }; return false },
           "sin integrado: queda el del sistema")
    expectEq(MicChoice.captureID(preference: .device(id: "gone", name: "X"), snapshot: both),
             nil, "captura: ausente, el sistema")
}

@Test func theChoiceReturnsWhenTheDeviceComesBack() {
    let pref = MicPreference.device(id: "usb", name: "USB")
    let away = MicDeviceSnapshot(
        devices: [MicInput(id: "mac", name: "Mac", builtIn: true)],
        systemDefaultName: "Mac")
    let back = MicDeviceSnapshot(devices: [
        MicInput(id: "mac", name: "Mac", builtIn: true),
        MicInput(id: "usb", name: "USB", builtIn: false),
    ], systemDefaultName: "Mac")
    expectEq(MicChoice.captureID(preference: pref, snapshot: away), nil, "vuelve: mientras falta, el sistema")
    let resolved = MicChoice.resolve(pref, back)
    expectEq(resolved.captureID, "usb", "vuelve: el id elegido")
    expectEq(resolved.missingName, nil, "vuelve: ya no falta")
    let row = resolved.rows.first { if case .device(let id, _, _) = $0 { return id == "usb" }; return false }
    expectEq(row?.selected, true, "vuelve: la fila queda elegida")
}

@Test func anUnreadableOrEmptyStoredChoiceIsTheBuiltInMic() {
    let (name, defaults) = suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let store = MicPreferenceStore(defaults: defaults)
    let emptyID = Data(#"{"device":{"id":"","name":"Blue"}}"#.utf8)
    defaults.set(emptyID, forKey: MicPreferenceStore.key)
    expectEq(store.load(), .builtIn, "preferencia: id vacío vuelve al del equipo")
    let emptyName = Data(#"{"device":{"id":"usb","name":""}}"#.utf8)
    defaults.set(emptyName, forKey: MicPreferenceStore.key)
    expectEq(store.load(), .builtIn, "preferencia: nombre vacío vuelve al del equipo")
    expect(store.save(.builtIn), "preferencia: guardar el del equipo se confirma")
    expectEq(MicPreferenceStore(defaults: defaults).load(), .builtIn, "preferencia: el del equipo se lee")
}

@Test func theStoredShapeIsFixed() {
    let (name, defaults) = suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let store = MicPreferenceStore(defaults: defaults)
    // A renamed case would silently reset every saved choice; this literal
    // is what a released build already wrote.
    defaults.set(Data(#"{"device":{"id":"usb","name":"Blue"}}"#.utf8), forKey: MicPreferenceStore.key)
    expectEq(store.load(), .device(id: "usb", name: "Blue"), "forma: un dispositivo guardado se lee")
    defaults.set(Data(#"{"builtIn":{}}"#.utf8), forKey: MicPreferenceStore.key)
    expectEq(store.load(), .builtIn, "forma: el del equipo se lee")
    defaults.set(Data(#"{"systemDefault":{}}"#.utf8), forKey: MicPreferenceStore.key)
    expectEq(store.load(), .systemDefault, "forma: el del sistema se lee")
}

@Test func theBuiltInChoiceStillPinsTheBuiltInMicWhenTheListIsEmpty() {
    expectEq(MicChoice.target(preference: .builtIn, snapshot: .empty), .builtIn,
             "lista vacía: el del equipo no cae al del sistema")
    let mac = MicDeviceSnapshot(
        devices: [MicInput(id: "mac", name: "Mac", builtIn: true)], systemDefaultName: "Mac")
    expectEq(MicChoice.target(preference: .builtIn, snapshot: mac), .device("mac"),
             "lista leída: el integrado concreto")
    expectEq(MicChoice.target(preference: .systemDefault, snapshot: mac), .systemDefault,
             "sistema: sin id")
    expectEq(MicChoice.target(preference: .device(id: "gone", name: "X"), snapshot: mac), .systemDefault,
             "ausente: el del sistema")
}

@Test func theRouteChangesOnlyWhenTheInputDoes() {
    let usb = MicInput(id: "usb", name: "USB", builtIn: false)
    let mac = MicInput(id: "mac", name: "Mac", builtIn: true)
    let before = MicDeviceSnapshot(devices: [mac, usb], systemDefaultName: "Mac")
    let pref = MicPreference.device(id: "usb", name: "USB")
    let route = MicChoice.route(preference: pref, snapshot: before)
    let extra = MicDeviceSnapshot(
        devices: [mac, usb, MicInput(id: "z", name: "Z", builtIn: false)], systemDefaultName: "Mac")
    expectEq(MicChoice.route(preference: pref, snapshot: extra), route, "ruta: otro dispositivo no la cambia")
    let defaultMoved = MicDeviceSnapshot(devices: [mac, usb], systemDefaultName: "USB")
    expectEq(MicChoice.route(preference: pref, snapshot: defaultMoved), route,
             "ruta: un id elegido no sigue al del sistema")
    let gone = MicDeviceSnapshot(devices: [mac], systemDefaultName: "Mac")
    expectEq(MicChoice.route(preference: pref, snapshot: gone).target, .systemDefault, "ruta: ausente, el sistema")
    let system = MicChoice.route(preference: .systemDefault, snapshot: before)
    expectEq(system.systemName, "Mac", "ruta: el del sistema lleva su nombre")
    expect(MicChoice.route(preference: .systemDefault, snapshot: defaultMoved) != system,
           "ruta: si el del sistema se mueve, la ruta cambia")
}
