import CompanionCore
import Foundation
import Observation

/// State of the reset dialog. It decides when the danger button is live and
/// owns the one in-flight run; the process work stays behind the port.
@Observable
@MainActor
package final class ResetPermissionsModel {
    package enum Phase: Equatable {
        case idle, running
        /// The typed error is kept: a partial reset and a failed relaunch
        /// need different words.
        case failed(PermissionResetError)
    }

    package private(set) var phase: Phase = .idle
    private let port: any PermissionResetting

    package init(port: any PermissionResetting) {
        self.port = port
    }

    package var isRunning: Bool { phase == .running }

    package var failure: PermissionResetError? {
        if case .failed(let error) = phase { return error }
        return nil
    }

    package var failedService: PermissionResetService? {
        if case .resetFailed(let service) = failure { return service }
        return nil
    }

    /// What the failed run had already wiped.
    package var clearedServices: [PermissionResetService] {
        failedService.map(PermissionReset.cleared(before:)) ?? []
    }

    package func canConfirm(input: String, language: AppLanguage) -> Bool {
        ResetDialogState.confirmEnabled(phase: phase, input: input, language: language)
    }

    /// On success the port quits the app; a port that returns (a fake) just
    /// leaves the dialog idle. A throw that is not typed is shown as the
    /// generic failure, which claims nothing about what was reset.
    package func confirm(input: String, language: AppLanguage) async {
        guard canConfirm(input: input, language: language) else { return }
        phase = .running
        do {
            try await port.resetAndRelaunch()
            phase = .idle
        } catch let error as PermissionResetError {
            phase = .failed(error)
        } catch {
            phase = .failed(.unexpected)
        }
    }

    package func dismissError() {
        if case .failed = phase { phase = .idle }
    }
}

/// What the dialog shows and allows per phase and language. Pure, so the
/// view only paints it.
package enum ResetDialogState {
    package static func promptWord(language: AppLanguage) -> String {
        PermissionReset.confirmationWord(for: language)
    }

    package static func confirmEnabled(
        phase: ResetPermissionsModel.Phase, input: String, language: AppLanguage
    ) -> Bool {
        phase != .running && PermissionReset.isConfirmed(input, language: language)
    }

    /// The close button, Cancel and the field: nothing closes mid-run, a
    /// half-finished reset must not be left unattended.
    package static func closeEnabled(phase: ResetPermissionsModel.Phase) -> Bool {
        phase != .running
    }

    /// A switch with no default: a service added without a label stops
    /// compiling here.
    package static func labelKey(_ service: PermissionResetService) -> String {
        switch service {
        case .microphone: "settings.resetPermissions.service.microphone"
        case .speechRecognition: "settings.resetPermissions.service.speechRecognition"
        case .screenCapture: "settings.resetPermissions.service.screenCapture"
        case .accessibility: "settings.resetPermissions.service.accessibility"
        case .listenEvent: "settings.resetPermissions.service.listenEvent"
        case .addressBook: "settings.resetPermissions.service.addressBook"
        case .appleEvents: "settings.resetPermissions.service.appleEvents"
        }
    }

    package static func permissionList(
        _ services: [PermissionResetService], language: AppLanguage
    ) -> String {
        services.map { Localized.string(labelKey($0), language: language) }
            .joined(separator: ", ")
    }

    /// The dialog's "this resets" sentence, built from the real plan.
    package static func resetsText(language: AppLanguage) -> String {
        String(
            format: Localized.string("settings.resetPermissions.dialog.resets", language: language),
            permissionList(PermissionResetService.allCases, language: language))
    }

    package static func errorText(for error: PermissionResetError, language: AppLanguage) -> String {
        func string(_ key: String) -> String {
            Localized.string("settings.resetPermissions.\(key)", language: language)
        }
        switch error {
        case .resetFailed(let service):
            let cleared = PermissionReset.cleared(before: service)
            let failed = Localized.string(labelKey(service), language: language)
            if cleared.isEmpty {
                return String(format: string("error.resetFirst"), failed)
            }
            return String(
                format: string("error.resetPartial"), failed,
                permissionList(cleared, language: language))
        case .relaunchFailed:
            return string("error.relaunch")
        case .invalidBundleID, .invalidBundlePath, .invalidPID, .unexpected:
            return string("error")
        }
    }
}
