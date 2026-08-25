import CompanionCore
import SwiftUI

/// First run. The key used to be the only door; now it is the upgrade, and the
/// screen shows whichever way in this Mac actually has.
public struct OnboardingView: View {
    @Bindable var model: ChatViewModel

    public init(model: ChatViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x6) {
            // The mascot greets on first run: the app's face before it has
            // anything to say.
            MascotView(excited: model.onboardingBusy)
                .frame(maxWidth: .infinity)
                .frame(height: 180)

            VStack(alignment: .leading, spacing: Space.x3) {
                Text("Companion")  // token-exempt: nombre del producto.
                    .font(.uiHeading)
                    .foregroundStyle(Semantic.foreground)

                Text(blurb)
                    .font(.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
            }

            localSection

            keySection

            Spacer()
        }
        .padding(Space.x6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The headline follows the state: promising a local model before the
    /// probe answers is how a launch ends up contradicting itself.
    private var blurb: String {
        switch model.startup {
        case .probing:
            return Localized.string("onboarding.probing")
        case .base:
            return Localized.string("onboarding.base.blurb")
        case .none, .premium:
            return Localized.string("onboarding.blurb")
        }
    }

    @ViewBuilder private var localSection: some View {
        switch model.startup {
        case .probing:
            HStack(spacing: Space.x2) {
                ProgressView()
                    .frame(width: 12, height: 12)
                Text(Localized.string("onboarding.probing"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        case .base(let paths):
            VStack(alignment: .leading, spacing: Space.x2) {
                ForEach(paths, id: \.providerName) { path in
                    AppButton(pathTitle(path)) {
                        model.acceptLocalBase(path)
                    }
                }
            }
        case .none:
            Text(Localized.string("onboarding.local.missing"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
        case .premium:
            EmptyView()
        }
    }

    private func pathTitle(_ path: LocalPath) -> String {
        guard let model = path.model else {
            return Localized.string("onboarding.local.apple")
        }
        return String(format: Localized.string("onboarding.local.ollama"), model)
    }

    @ViewBuilder private var keySection: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(Localized.string("onboarding.key.optional"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)

            AppField(
                title: Localized.string("onboarding.key"),
                placeholder: "sk-proj-...",
                text: $model.onboardingKey,
                error: model.onboardingBusy ? nil : model.errorText,
                secure: true,
                onSubmit: { Task { await model.submitOnboarding() } })

            HStack(spacing: Space.x2) {
                Text(Localized.string("onboarding.getKey"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.accentText)
                Link("", destination: URL(string: "https://platform.openai.com/api/keys")!)
                    .frame(height: 16)
            }

            if model.onboardingBusy {
                HStack(spacing: Space.x2) {
                    ProgressView()
                        .frame(width: 12, height: 12)
                    Text(Localized.string("onboarding.verifying"))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            }

            HStack(spacing: Space.x3) {
                AppButton(
                    Localized.string("onboarding.continue"),
                    kind: hasLocalPath ? .secondary : .primary,
                    enabled: !cannotContinue
                ) {
                    Task { await model.submitOnboarding() }
                }
                Spacer()
            }
        }
    }

    private var hasLocalPath: Bool {
        if case .base = model.startup { return true }
        return false
    }

    private var cannotContinue: Bool {
        model.onboardingBusy
            || model.onboardingKey.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }
}
