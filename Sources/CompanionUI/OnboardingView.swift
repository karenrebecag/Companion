import CompanionCore
import SwiftUI

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

                Text(Localized.string("onboarding.blurb"))
                    .font(.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
            }

            VStack(alignment: .leading, spacing: Space.x2) {
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
                    "Continuar",
                    enabled: !cannotContinue
                ) {
                    Task { await model.submitOnboarding() }
                }
                Spacer()
            }

            Spacer()
        }
        .padding(Space.x6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cannotContinue: Bool {
        model.onboardingBusy
            || model.onboardingKey.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }
}
