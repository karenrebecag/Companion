import CompanionCore
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing

@testable import CompanionUI

// ON-18. The row's logic and copy; the port is a fake, so no process runs.

private final class FakePort: PermissionResetting, @unchecked Sendable {
    let calls = LockedBox(0)
    let result: PermissionResetError?
    init(failing result: PermissionResetError? = nil) { self.result = result }
    func resetAndRelaunch() async throws {
        calls.value += 1
        if let result { throw result }
    }
}

private final class GatedPort: PermissionResetting, @unchecked Sendable {
    let calls = LockedBox(0)
    private let gate: AsyncStream<Void>
    init(gate: AsyncStream<Void>) { self.gate = gate }
    func resetAndRelaunch() async throws {
        calls.value += 1
        for await _ in gate { break }
    }
}

@MainActor private func copy(_ key: String, _ language: AppLanguage) async -> String {
    await pinLanguage(language) { Localized.string(key) }
}

@MainActor private func label(_ service: PermissionResetService, _ language: AppLanguage) -> String {
    Localized.string(ResetDialogState.labelKey(service), language: language)
}

@Test @MainActor func resetPermissionsModelRunsThePortOnlyWhenTheWordMatches() async {
    let port = FakePort()
    let model = ResetPermissionsModel(port: port)
    expect(!model.canConfirm(input: "", language: .en), "model: empty input stays locked")
    expect(!model.canConfirm(input: "RESTABLECER", language: .en), "model: wrong language locked")
    expect(model.canConfirm(input: "reset", language: .en), "model: en word unlocks")
    await model.confirm(input: "nope", language: .en)
    expectEq(port.calls.value, 0, "model: a wrong word never reaches the port")
    expectEq(model.phase, .idle, "model: still idle")
    await model.confirm(input: "RESET", language: .en)
    expectEq(port.calls.value, 1, "model: right word runs the port once")
}

@Test @MainActor func resetPermissionsModelKeepsTheTypedFailure() async {
    let failed = PermissionResetService.allCases[3]
    let model = ResetPermissionsModel(port: FakePort(failing: .resetFailed(failed)))
    await model.confirm(input: "RESET", language: .en)
    expectEq(model.phase, .failed(.resetFailed(failed)), "model: the typed error survives")
    expect(!model.isRunning, "model: buttons free again after failure")
    expectEq(model.failedService, failed, "model: exposes the service that failed")
    expectEq(model.clearedServices, Array(PermissionResetService.allCases.prefix(3)),
             "model: exposes what was already cleared")
    model.dismissError()
    expectEq(model.phase, .idle, "model: error can be dismissed")
    expectEq(model.failedService, nil, "model: nothing failed after dismiss")
    expectEq(model.clearedServices, [], "model: nothing cleared after dismiss")
}

@Test @MainActor func resetPermissionsPartialFailureCopyNamesWhatWasAndWasNotReset() {
    let all = PermissionResetService.allCases
    let error = PermissionResetError.resetFailed(all[3])
    for language in AppLanguage.allCases {
        let text = ResetDialogState.errorText(for: error, language: language)
        expect(text.contains(label(all[3], language)), "partial \(language): names the failed one")
        for cleared in all.prefix(3) {
            expect(text.contains(label(cleared, language)),
                   "partial \(language): lists \(cleared) as already reset")
        }
        for later in all.suffix(from: 4) {
            expect(!text.contains(label(later, language)),
                   "partial \(language): does not claim \(later)")
        }
    }
    expect(ResetDialogState.errorText(for: error, language: .en).contains("already reset"),
           "partial en: says so")
    expect(ResetDialogState.errorText(for: error, language: .es).contains("ya se restablecieron"),
           "partial es: says so")
}

@Test @MainActor func resetPermissionsFirstServiceFailureClaimsNothingWasReset() {
    let error = PermissionResetError.resetFailed(PermissionResetService.allCases[0])
    let en = ResetDialogState.errorText(for: error, language: .en)
    let es = ResetDialogState.errorText(for: error, language: .es)
    expect(en.contains(label(.microphone, .en)) && !en.contains("already reset"),
           "first en: names it, lists nothing")
    expect(es.contains(label(.microphone, .es)) && !es.contains("ya se restablecieron"),
           "first es: names it, lists nothing")
}

@Test @MainActor func resetPermissionsRelaunchFailureSaysThePermissionsWereReset() async {
    let model = ResetPermissionsModel(port: FakePort(failing: .relaunchFailed))
    await model.confirm(input: "RESET", language: .en)
    expectEq(model.phase, .failed(.relaunchFailed), "model: relaunch failure is kept")
    expectEq(model.failedService, nil, "model: no service failed")
    let en = ResetDialogState.errorText(for: .relaunchFailed, language: .en)
    let es = ResetDialogState.errorText(for: .relaunchFailed, language: .es)
    expect(en.contains("were reset") && en.contains("Open Companion again"),
           "relaunch en: permissions were reset, reopen by hand")
    expect(es.contains("se restablecieron") && es.contains("Ábrelo"),
           "relaunch es: permissions were reset, reopen by hand")
    expect(!en.contains("was not relaunched"), "relaunch en: no false 'not reset' claim")
    let generic = ResetDialogState.errorText(for: .invalidBundleID, language: .en)
    expect(en != generic, "relaunch en: its own copy")
    expect(es != ResetDialogState.errorText(for: .invalidBundleID, language: .es),
           "relaunch es: its own copy")
}

@Test @MainActor func resetPermissionsModelIgnoresASecondConfirmWhileRunning() async {
    let (opened, release) = AsyncStream<Void>.makeStream()
    let port = GatedPort(gate: opened)
    let model = ResetPermissionsModel(port: port)
    let first = Task { await model.confirm(input: "RESET", language: .en) }
    while port.calls.value == 0 { await Task.yield() }
    expect(model.isRunning, "model: running while the port works")
    expect(!model.canConfirm(input: "RESET", language: .en), "model: locked while running")
    await model.confirm(input: "RESET", language: .en)
    expectEq(port.calls.value, 1, "model: no second run while one is in flight")
    release.yield()
    release.finish()
    await first.value
    expectEq(model.phase, .idle, "model: back to idle after success")
}

@Test @MainActor func resetDialogStateDecidesControlsPerPhaseAndLanguage() {
    let failed = ResetPermissionsModel.Phase.failed(.relaunchFailed)
    for phase in [ResetPermissionsModel.Phase.idle, failed] {
        expect(ResetDialogState.closeEnabled(phase: phase), "state: close is live in \(phase)")
        expect(ResetDialogState.confirmEnabled(phase: phase, input: "reset", language: .en),
               "state: right word unlocks in \(phase)")
        expect(!ResetDialogState.confirmEnabled(phase: phase, input: "", language: .en),
               "state: empty stays locked in \(phase)")
    }
    expect(!ResetDialogState.closeEnabled(phase: .running), "state: no close while running")
    expect(!ResetDialogState.confirmEnabled(phase: .running, input: "RESET", language: .en),
           "state: no confirm while running")
    expectEq(ResetDialogState.promptWord(language: .en), "RESET", "state: en word")
    expectEq(ResetDialogState.promptWord(language: .es), "RESTABLECER", "state: es word")
    expect(!ResetDialogState.confirmEnabled(phase: .idle, input: "RESET", language: .es),
           "state: the other language's word stays locked")
}

@Test @MainActor func resetPermissionsDialogWidthIsPinnedToIncredibles480() {
    expectEq(ResetPermissionsMetrics.dialogMaxWidth, 480, "metrics: dialog width")
}

@Test @MainActor func resetPermissionsCopyExistsInBothLanguages() async {
    let keys = [
        "settings.resetPermissions.title", "settings.resetPermissions.body",
        "settings.resetPermissions.button", "settings.resetPermissions.dialog.title",
        "settings.resetPermissions.dialog.resets", "settings.resetPermissions.dialog.keeps",
        "settings.resetPermissions.dialog.prompt", "settings.resetPermissions.dialog.confirm",
        "settings.resetPermissions.dialog.cancel", "settings.resetPermissions.dialog.running",
        "settings.resetPermissions.error", "settings.resetPermissions.error.resetFirst",
        "settings.resetPermissions.error.resetPartial", "settings.resetPermissions.error.relaunch",
    ] + PermissionResetService.allCases.map(ResetDialogState.labelKey)
    for key in keys {
        let en = await copy(key, .en)
        let es = await copy(key, .es)
        expect(en != key && !en.isEmpty, "copy: \(key) exists in en")
        expect(es != key && !es.isEmpty, "copy: \(key) exists in es")
        expect(en != es, "copy: \(key) differs between languages")
    }
}

// Tied to allCases: a service added without a label key fails here, and the
// switch in labelKey fails to compile before that.
@Test @MainActor func resetPermissionsDialogListsEveryServiceInBothLanguages() {
    for language in AppLanguage.allCases {
        let text = ResetDialogState.resetsText(language: language)
        for service in PermissionResetService.allCases {
            expect(text.contains(label(service, language)),
                   "copy \(language): the dialog lists \(service)")
        }
    }
    let labels = PermissionResetService.allCases.map(ResetDialogState.labelKey)
    expectEq(Set(labels).count, PermissionResetService.allCases.count, "copy: one key per service")
    let en = ResetDialogState.resetsText(language: .en)
    for name in ["Microphone", "Speech Recognition", "Screen Recording", "Accessibility",
                 "Input Monitoring", "Contacts", "Automation"] {
        expect(en.contains(name), "copy en: \(name)")
    }
    let es = ResetDialogState.resetsText(language: .es)
    for name in ["Micrófono", "Reconocimiento de voz", "Grabación de pantalla", "Accesibilidad",
                 "Monitoreo de entrada", "Contactos", "Automatización"] {
        expect(es.contains(name), "copy es: \(name)")
    }
}

@Test @MainActor func resetPermissionsCopyStatesPermissionsOnlyAndSpecificWords() async {
    expectEq(await copy("settings.resetPermissions.title", .es),
             "Restablecer permisos de Companion", "copy: es title")
    expectEq(await copy("settings.resetPermissions.title", .en),
             "Reset Companion's permissions", "copy: en title")
    expectEq(await copy("settings.resetPermissions.body", .es),
             "Borra los permisos que diste en este Mac y reinicia Companion para pedirlos de nuevo.",
             "copy: es body")
    let enKeeps = await copy("settings.resetPermissions.dialog.keeps", .en)
    expect(enKeeps.contains("settings") && enKeeps.contains("keys")
           && enKeeps.contains("conversations"), "copy: lists what is kept")
    expectEq(await copy("settings.resetPermissions.dialog.confirm", .en),
             "Reset and relaunch", "copy: en confirm")
    expectEq(await copy("settings.resetPermissions.dialog.confirm", .es),
             "Restablecer y reiniciar", "copy: es confirm")
}
