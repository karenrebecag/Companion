import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 10a §3.6. La fila de permiso es un modelo puro: estado, si hay botón,
// y a dónde lleva. El único prompt del sistema lo dispara la usuaria.
@Test @MainActor func permissionRowTests() async {
    await pinLanguage {
        testRowShowsButtonOnlyWhenNotGranted()
        testDocumentsToggleRequestsOnce()
        testVoiceFailureOffersTheRightLink()
    }
}

@MainActor func testRowShowsButtonOnlyWhenNotGranted() {
    let denied = PermissionRowModel(kind: .accessibility, granted: false)
    expectEq(denied.status, Localized.string("permission.denied"), "fila: sin conceder")
    expect(denied.showsButton, "fila: sin conceder hay botón")
    expectEq(denied.link, PermissionSettingsLink.accessibility, "fila: lleva a Accesibilidad")
    expectEq(denied.title, Localized.string("permission.accessibility.title"), "fila: título")
    let granted = PermissionRowModel(kind: .accessibility, granted: true)
    expectEq(granted.status, Localized.string("permission.granted"), "fila: concedido")
    expect(!granted.showsButton, "fila: concedido, sin botón")
    expectEq(PermissionRowModel(kind: .microphone, granted: false).link,
             PermissionSettingsLink.microphone, "fila: el mic lleva a Micrófono")
    expectEq(PermissionRowModel(kind: .screenRecording, granted: false).link,
             PermissionSettingsLink.screenRecording, "fila: pantalla lleva a Grabación")
}

/// Encender documentos sin permiso pide el prompt UNA vez y deja el toggle
/// encendido: el sensor degrada solo; el toggle es la intención de la usuaria.
@MainActor func testDocumentsToggleRequestsOnce() {
    let ax = FakeAccessibility(trusted: false)
    ContextPreference.store = UserDefaults(suiteName: "companion.tests.context")!
    defer { ContextPreference.store = .standard }
    ContextPreference.store.removePersistentDomain(forName: "companion.tests.context")
    ContextPreference.channels = [.focusedApp]
    let model = ContextSettingsModel(accessibility: ax)
    expect(!model.documents, "toggle: arranca apagado")
    model.documents = true
    expectEq(ax.requests, 1, "toggle: pidió el prompt una vez")
    expect(model.documents, "toggle: queda encendido aunque no haya permiso")
    expect(ContextPreference.channels.contains(.openDocuments), "toggle: la preferencia guarda la intención")
    expect(!model.accessibilityGranted, "toggle: el estado dice la verdad")
    model.documents = false
    model.documents = true
    expectEq(ax.requests, 2, "toggle: cada encendido sin permiso vuelve a pedir — el deep link está siempre")
    ax.trusted = true
    model.refreshTrust()
    expect(model.accessibilityGranted, "toggle: refresca al volver de Ajustes")
    model.documents = false
    model.documents = true
    expectEq(ax.requests, 2, "toggle: con permiso no pide")
    model.clipboard = true
    expect(ContextPreference.channels.contains(.clipboard), "toggle: portapapeles")
    model.location = true
    expect(model.location && ContextPreference.channels.contains(.location), "toggle: ubicación encendida")
    model.location = false
    expect(!model.location && !ContextPreference.channels.contains(.location), "toggle: ubicación apagada")
}

@MainActor func testVoiceFailureOffersTheRightLink() {
    expectEq(VoiceCopy.settingsLink(for: .micDenied), PermissionSettingsLink.microphone,
             "voz: mic negado lleva a Micrófono")
    expectEq(VoiceCopy.settingsLink(for: .speechDenied), PermissionSettingsLink.speechRecognition,
             "voz: dictado negado lleva a Reconocimiento de voz")
    expect(VoiceCopy.settingsLink(for: .notHeard) == nil, "voz: no oír no es un permiso")
    expect(VoiceCopy.settingsLink(for: nil) == nil, "voz: sin fallo, sin enlace")
}

