import CompanionCore
import SwiftUI

/// The page's step before the function exists: what is missing, and one
/// way to fix it. Same card as the page header, so it reads as part of it.
struct AppsSetupBanner: View {
    let onSetUp: () -> Void

    var body: some View {
        HStack(spacing: Space.x4) {
            Image(systemName: "link")
                .font(.uiBody.weight(.medium))
                .foregroundStyle(Semantic.foreground)
                .frame(width: AppsSetupMetrics.bannerIcon, height: AppsSetupMetrics.bannerIcon)
                .background(RoundedRectangle(cornerRadius: AppsMetrics.iconRadius).fill(Semantic.hover))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.x0_5) {
                Text(Localized.string("apps.setup.title"))
                    .font(.uiLabel.weight(.semibold))
                    .foregroundStyle(Semantic.foreground)
                Text(Localized.string("apps.seed.banner"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.x4)
            AppButton(Localized.string("apps.seed.configure"), action: onSetUp)
        }
        .padding(Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Semantic.surface)
        .clipShape(RoundedRectangle(cornerRadius: CardChrome.radius))
        .overlay(RoundedRectangle(cornerRadius: CardChrome.radius)
            .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
        .elevation(.hover)
        .accessibilityElement(children: .contain)
    }
}

/// The function's address and key. The key field never shows what is
/// stored: a confirmed save clears it.
struct AppsSetupForm: View {
    @State private var controller: AppsSetupController
    let onSaved: () -> Void

    init(apps: AppsModel, initialEndpoint: String, onSaved: @escaping () -> Void) {
        self._controller = State(initialValue: AppsSetupController(apps: apps, endpoint: initialEndpoint))
        self.onSaved = onSaved
    }

    var body: some View {
        @Bindable var controller = controller
        AppsSetupCard(flow: controller.flow, endpoint: $controller.endpoint, key: $controller.key) {
            Task { await controller.submit() }
        }
        .task(id: controller.flow.phase == .confirmed) {
            guard controller.flow.phase == .confirmed else { return }
            do {
                try await Task.sleep(for: .seconds(AppsSetupMetrics.confirmHold))
            } catch {
                return
            }
            onSaved()
        }
    }
}

/// The form drawn from its state alone, so the gallery can show each phase.
/// Two faces on one card, after Arc contact-section's form-to-confirmation morph.
struct AppsSetupCard: View {
    let flow: AppsSetupFlow
    @Binding var endpoint: String
    @Binding var key: String
    let onSubmit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Messages: Equatable {
        var endpoint: AppsSetupIssue?
        var key: AppsSetupIssue?
        var failure: AppsSetupFlow.Failure?
    }

    var body: some View {
        let motion = AppsSetupMotion.resolve(reduceMotion: reduceMotion)
        ZStack(alignment: .top) {
            if flow.phase == .confirmed {
                confirmation.transition(motion.faceTransition)
            } else {
                form(motion).transition(motion.faceTransition)
            }
        }
        .padding(Space.x6)
        .frame(maxWidth: AppsMetrics.formWidth, alignment: .leading)
        .background(Semantic.surface)
        .clipShape(RoundedRectangle(cornerRadius: CardChrome.radius))
        .overlay(RoundedRectangle(cornerRadius: CardChrome.radius)
            .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
        .elevation(.hover)
        .animation(motion.faceAnimation, value: flow.phase == .confirmed)
    }

    private func form(_ motion: AppsSetupMotion) -> some View {
        let endpointIssue = flow.endpointError(endpoint)
        let keyIssue = flow.keyError(key)
        let saving = flow.phase == .saving
        return VStack(alignment: .leading, spacing: Space.x4) {
            VStack(alignment: .leading, spacing: Space.x1_5) {
                Text(Localized.string("apps.setup.title"))
                    .font(.uiLabel.weight(.semibold))
                    .foregroundStyle(Semantic.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text(Localized.string("apps.setup.body"))
                    .typeRole(.body)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AppField(title: Localized.string("apps.setup.endpoint"),
                     placeholder: Localized.string("apps.setup.endpoint.placeholder"), text: $endpoint,
                     description: AppsSetupCopy.endpointHelp, error: endpointIssue.map(AppsSetupCopy.issue),
                     readOnly: flow.isReadOnly, messageTransition: motion.messageTransition,
                     messagesInHint: true, onSubmit: onSubmit)
            AppField(title: Localized.string("apps.setup.key"),
                     placeholder: Localized.string("apps.setup.key.placeholder"), text: $key,
                     description: AppsSetupCopy.keyHelp, error: keyIssue.map(AppsSetupCopy.issue), secure: true,
                     readOnly: flow.isReadOnly, messageTransition: motion.messageTransition,
                     messagesInHint: true, onSubmit: onSubmit)
            if let failure = flow.failure {
                Text(AppsSetupCopy.failure(failure))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(motion.messageTransition)
            }
            AppButton(saving ? AppsSetupCopy.saving : Localized.string("apps.setup.save"),
                      enabled: !flow.isReadOnly, busy: saving, action: onSubmit)
        }
        .animation(motion.messageAnimation,
                   value: Messages(endpoint: endpointIssue, key: keyIssue, failure: flow.failure))
    }

    private var confirmation: some View {
        VStack(spacing: Space.x3) {
            Image(systemName: "checkmark")
                .font(.uiSubtitle.weight(.semibold))
                .foregroundStyle(Semantic.success)
                .frame(width: AppsSetupMetrics.mark, height: AppsSetupMetrics.mark)
                .background(Circle().fill(Semantic.successMuted))
                .accessibilityHidden(true)
            VStack(spacing: Space.x1) {
                Text(AppsSetupCopy.doneTitle)
                    .font(.uiLabel.weight(.semibold))
                    .foregroundStyle(Semantic.foreground)
                Text(AppsSetupCopy.doneBody)
                    .typeRole(.body)
                    .foregroundStyle(Semantic.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.x6)
        .accessibilityElement(children: .combine)
    }
}
