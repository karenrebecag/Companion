import CompanionCore
import SwiftUI

public struct OnboardingView: View {
    @Bindable var model: ChatViewModel

    public init(model: ChatViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s16) {
            Text("Companion")
                .font(Tokens.Typography.title)
                .foregroundStyle(Tokens.Color.fg)
            Text(ChatCopy.emptyKey)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.muted)
            SecureField("Clave de OpenAI", text: $model.onboardingKey)
                .textFieldStyle(.plain)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.fg)
                .padding(Tokens.Space.s8)
                .background(Tokens.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Tokens.Color.border, lineWidth: 1)
                )
                .onSubmit {
                    Task { await model.submitOnboarding() }
                }
            if let error = model.errorText {
                Text(error)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.destructive)
            }
            Button("Continuar") {
                Task { await model.submitOnboarding() }
            }
            .font(Tokens.Typography.body)
            .foregroundStyle(Tokens.Color.fg)
            .disabled(cannotContinue)
        }
        .padding(Tokens.Space.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cannotContinue: Bool {
        model.onboardingBusy
            || model.onboardingKey.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }
}
