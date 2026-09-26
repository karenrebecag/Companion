import CompanionCore
import SwiftUI

/// A permission as a row, not a surprise dialog (spec 10a §3.6, from the
/// corpus's spec 28): what it is for, whether it is granted, and a way to
/// System Settings that never runs out — the system prompt shows once.
public struct PermissionRowModel: Equatable {
    public enum Kind: Equatable {
        case accessibility, microphone, speechRecognition, inputMonitoring, screenRecording
    }

    public var kind: Kind
    public var granted: Bool

    public init(kind: Kind, granted: Bool) {
        self.kind = kind
        self.granted = granted
    }

    public var title: String {
        switch kind {
        case .accessibility: Localized.string("permission.accessibility.title")
        case .microphone: Localized.string("permission.microphone.title")
        case .speechRecognition: Localized.string("permission.speech.title")
        case .inputMonitoring: Localized.string("permission.inputMonitoring.title")
        case .screenRecording: Localized.string("permission.screenRecording.title")
        }
    }

    public var body: String {
        switch kind {
        case .accessibility: Localized.string("permission.accessibility.body")
        case .microphone: Localized.string("permission.microphone.body")
        case .speechRecognition: Localized.string("permission.speech.body")
        case .inputMonitoring: Localized.string("permission.inputMonitoring.body")
        case .screenRecording: Localized.string("permission.screenRecording.body")
        }
    }

    public var status: String {
        Localized.string(granted ? "permission.granted" : "permission.denied")
    }

    public var showsButton: Bool { !granted }

    public var link: URL {
        switch kind {
        case .accessibility: PermissionSettingsLink.accessibility
        case .microphone: PermissionSettingsLink.microphone
        case .speechRecognition: PermissionSettingsLink.speechRecognition
        case .inputMonitoring: PermissionSettingsLink.inputMonitoring
        case .screenRecording: PermissionSettingsLink.screenRecording
        }
    }
}

public struct PermissionRow: View {
    @Environment(\.openURL) private var openURL
    var model: PermissionRowModel

    public init(model: PermissionRowModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                Text(model.title)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                Spacer(minLength: Space.x2)
                Text(model.status)
                    .font(.uiCaption)
                    .foregroundStyle(model.granted ? Semantic.accentText : Semantic.mutedForeground)
            }
            Text(model.body)
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if model.showsButton {
                Button(Localized.string("permission.open")) { openURL(model.link) }
                    .buttonStyle(.link)
                    .font(.uiCaption)
            }
        }
    }
}
