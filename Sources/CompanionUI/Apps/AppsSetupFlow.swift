import CompanionCore
import SwiftUI

/// The setup form's own measures, after Arc's contact-section (uiarc.dev,
/// free registry: contact-section.json and arc-foundation's motion-tokens).
package enum AppsSetupMetrics {
    /// Arc's faces enter from 18 px along the axis; the nearest step on the ramp.
    package static let faceTravel: CGFloat = Space.x4
    /// Arc's leaving face moves 12 px the other way.
    package static let faceExitTravel: CGFloat = Space.x3
    /// Arc's `blur.soft` (4 px): small and brief, only while a face or a row moves.
    package static let blur: CGFloat = 4
    /// Arc input's message rises 0.35 em at its 12 px text.
    package static let messageRise: CGFloat = Space.x1
    /// The confirmation's mark: Arc's 52 px circle, on the ramp.
    package static let mark: CGFloat = Space.x12
    package static let bannerIcon: CGFloat = Space.x10
    /// Not motion: the beat the confirmation stays up before the catalog takes its place.
    package static let confirmHold = 1.2
}

/// What a field can be wrong about. Empty and malformed are told apart, as
/// Arc's contact form does, so the message says what to do next.
package enum AppsSetupIssue: Equatable, Sendable {
    case endpointEmpty, endpointInvalid, keyEmpty, keyShort
}

/// AppsModel.configure's own rules, read field by field so each one can
/// carry its own message. Nothing here is stricter or looser than configure.
package enum AppsSetupRules {
    package static func endpointIssue(_ text: String) -> AppsSetupIssue? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .endpointEmpty }
        guard let url = AppsEndpoint.validated(text), SecretHost.of(url: url.absoluteString) != nil else {
            return .endpointInvalid
        }
        return nil
    }

    package static func keyIssue(_ text: String) -> AppsSetupIssue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .keyEmpty }
        return trimmed.count < AppsModel.minimumKeyLength ? .keyShort : nil
    }
}

/// The form's phases (Arc contact-section: editing, sending, sent), plus the
/// failure it keeps on screen with the input intact.
package struct AppsSetupFlow: Equatable {
    package enum Failure: Equatable, Sendable {
        /// configure() refused values that pass the rules: the Keychain write failed.
        case storage
        case server(AppsFailure)
    }

    package enum Phase: Equatable, Sendable {
        case editing, saving, confirmed
        case failed(Failure)
    }

    package enum Outcome: Equatable, Sendable {
        case saved, storageFailed
        case serverFailed(AppsFailure)

        /// The save is only proven once the function answers the first load.
        package static func after(load phase: AppsModel.Phase) -> Outcome {
            switch phase {
            // HACK: .loading counts as saved because load() returns early, still
            // loading, when a search took the list over mid-flight; the form can
            // then confirm before the function has answered. Await the catalog
            // answer itself (not the phase) once load() reports its own result.
            case .ready, .loading: .saved
            case .failed(let failure): .serverFailed(failure)
            case .setup: .storageFailed
            }
        }
    }

    package private(set) var phase: Phase = .editing
    /// Arc's rule: nothing is wrong until the first submit, then errors follow the typing.
    private var attempted = false

    package init() {}

    package var failure: Failure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    package var isReadOnly: Bool { phase == .saving || phase == .confirmed }

    /// True when the caller should save now. False while a save is running,
    /// once confirmed, or when a field is wrong.
    package mutating func submit(endpoint: String, key: String) -> Bool {
        guard !isReadOnly else { return false }
        attempted = true
        guard AppsSetupRules.endpointIssue(endpoint) == nil, AppsSetupRules.keyIssue(key) == nil else {
            phase = .editing
            return false
        }
        phase = .saving
        return true
    }

    package mutating func finish(_ outcome: Outcome) {
        guard phase == .saving else { return }
        switch outcome {
        case .saved: phase = .confirmed
        case .storageFailed: phase = .failed(.storage)
        case .serverFailed(let failure): phase = .failed(.server(failure))
        }
    }

    /// What VoiceOver hears after a refused submit: the field to fix first,
    /// top to bottom, as Arc's form moves focus to it.
    package func announcedIssue(endpoint: String, key: String) -> AppsSetupIssue? {
        endpointError(endpoint) ?? keyError(key)
    }

    package func endpointError(_ text: String) -> AppsSetupIssue? {
        attempted ? AppsSetupRules.endpointIssue(text) : nil
    }

    package func keyError(_ text: String) -> AppsSetupIssue? {
        attempted ? AppsSetupRules.keyIssue(text) : nil
    }
}

/// The one reduced-motion decision for the form. Arc input: rows mount at
/// full height with an instant fade. Arc contact-section: faces swap
/// without travel, as a short fade.
package struct AppsSetupMotion {
    package let faceTravel: CGFloat
    package let faceExitTravel: CGFloat
    package let faceBlur: CGFloat
    package let faceAnimation: Animation
    package let faceExitAnimation: Animation
    package let messageRise: CGFloat
    package let messageBlur: CGFloat
    /// nil: the row and its height land at once.
    package let messageAnimation: Animation?

    package static func resolve(reduceMotion: Bool) -> AppsSetupMotion {
        if reduceMotion {
            return AppsSetupMotion(
                faceTravel: 0, faceExitTravel: 0, faceBlur: 0,
                faceAnimation: MotionCurve.animation(MotionCurve.linear, MotionTime.fast),
                faceExitAnimation: MotionCurve.animation(MotionCurve.linear, MotionTime.fast),
                messageRise: 0, messageBlur: 0, messageAnimation: nil)
        }
        // Arc's `smooth` spring (no bounce) carries the travel and the height;
        // sheet is the token closest to it.
        return AppsSetupMotion(
            faceTravel: AppsSetupMetrics.faceTravel, faceExitTravel: AppsSetupMetrics.faceExitTravel,
            faceBlur: AppsSetupMetrics.blur, faceAnimation: .springSheet,
            faceExitAnimation: MotionCurve.animation(MotionCurve.glide, MotionTime.fast),
            messageRise: AppsSetupMetrics.messageRise, messageBlur: AppsSetupMetrics.blur,
            messageAnimation: .springSheet)
    }

    /// Enters from below and settles out of the blur; leaves upward on
    /// Arc's fast standard ease, which is Companion's glide.
    package var faceTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SettleChrome(offset: faceTravel, blur: faceBlur, opacity: 0),
                identity: SettleChrome(offset: 0, blur: 0, opacity: 1)),
            removal: .modifier(
                active: SettleChrome(offset: -faceExitTravel, blur: faceBlur, opacity: 0),
                identity: SettleChrome(offset: 0, blur: 0, opacity: 1))
                .animation(faceExitAnimation))
    }

    package var messageTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SettleChrome(offset: messageRise, blur: messageBlur, opacity: 0),
                identity: SettleChrome(offset: 0, blur: 0, opacity: 1)),
            removal: .opacity)
    }
}

private struct SettleChrome: ViewModifier {
    var offset: CGFloat
    var blur: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

enum AppsSetupCopy {
    static func issue(_ issue: AppsSetupIssue) -> String {
        switch issue {
        case .endpointEmpty: Localized.string("apps.setup.endpoint.empty")
        case .endpointInvalid: Localized.string("apps.setup.endpoint.invalid")
        case .keyEmpty: Localized.string("apps.setup.key.empty")
        case .keyShort: String(format: Localized.string("apps.setup.key.short"), AppsModel.minimumKeyLength)
        }
    }

    static func failure(_ failure: AppsSetupFlow.Failure) -> String {
        switch failure {
        case .storage: Localized.string("apps.setup.storageFailed")
        case .server(let failure): AppsCopy.failure(failure)
        }
    }

    static var endpointHelp: String { Localized.string("apps.setup.endpoint.help") }
    static var keyHelp: String {
        String(format: Localized.string("apps.setup.key.help"), AppsModel.minimumKeyLength)
    }
    static var saving: String { Localized.string("apps.setup.saving") }
    static var doneTitle: String { Localized.string("apps.setup.done.title") }
    static var doneBody: String { Localized.string("apps.setup.done.body") }

    /// The new lines this form adds, for the parity test.
    static var fixed: [String] { [endpointHelp, keyHelp, saving, doneTitle, doneBody] }
}
