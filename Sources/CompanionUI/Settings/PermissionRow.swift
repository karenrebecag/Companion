import CompanionCore
import SwiftUI

/// A permission as a row, not a surprise dialog (spec 10a §3.6, from the
/// corpus's spec 28): what it is for, whether it is granted, and a way to
/// System Settings that never runs out — the system prompt shows once.
package struct PermissionRowModel: Equatable {
    package enum Kind: Equatable {
        case accessibility, microphone, speechRecognition, inputMonitoring, screenRecording
    }

    package var kind: Kind
    package var granted: Bool

    package init(kind: Kind, granted: Bool) {
        self.kind = kind
        self.granted = granted
    }

    package var title: String {
        switch kind {
        case .accessibility: Localized.string("permission.accessibility.title")
        case .microphone: Localized.string("permission.microphone.title")
        case .speechRecognition: Localized.string("permission.speech.title")
        case .inputMonitoring: Localized.string("permission.inputMonitoring.title")
        case .screenRecording: Localized.string("permission.screenRecording.title")
        }
    }

    package var body: String {
        switch kind {
        case .accessibility: Localized.string("permission.accessibility.body")
        case .microphone: Localized.string("permission.microphone.body")
        case .speechRecognition: Localized.string("permission.speech.body")
        case .inputMonitoring: Localized.string("permission.inputMonitoring.body")
        case .screenRecording: Localized.string("permission.screenRecording.body")
        }
    }

    package var status: String {
        Localized.string(granted ? "permission.granted" : "permission.denied")
    }

    package var showsButton: Bool { !granted }

    package var link: URL {
        switch kind {
        case .accessibility: PermissionSettingsLink.accessibility
        case .microphone: PermissionSettingsLink.microphone
        case .speechRecognition: PermissionSettingsLink.speechRecognition
        case .inputMonitoring: PermissionSettingsLink.inputMonitoring
        case .screenRecording: PermissionSettingsLink.screenRecording
        }
    }
}
