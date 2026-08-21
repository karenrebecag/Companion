import CompanionCore
import SwiftUI

public struct OnboardingView: View {
    @Bindable var model: ChatViewModel

    public init(model: ChatViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.x6) {
            VStack(alignment: .leading, spacing: Space.x3) {
                Text("Companion")
                    .font(.uiHeading)
                    .foregroundStyle(Semantic.foreground)

                Text("Tu voz privada asistente. Necesita tu clave de OpenAI.")
                    .font(.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
            }

            VStack(alignment: .leading, spacing: Space.x2) {
                Text("Clave de OpenAI")
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)

                SecureField("sk-proj-...", text: $model.onboardingKey)
                    .textFieldStyle(.plain)
                    .font(.uiBody)
                    .foregroundStyle(Semantic.foreground)
                    .padding(.horizontal, Space.x3)
                    .padding(.vertical, Space.x2)
                    .background(Semantic.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(keyBorderColor, lineWidth: Stroke.hairline)
                    )
                    .onSubmit {
                        Task { await model.submitOnboarding() }
                    }

                HStack(spacing: Space.x2) {
                    Text("Obtener clave")
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
                    Text("Verificando...")
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            } else if let error = model.errorText {
                Text(error)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.x3) {
                Button(action: { Task { await model.submitOnboarding() } }) {
                    Text("Continuar")
                        .font(.uiAction)
                        .foregroundStyle(Semantic.accentForeground)
                        .padding(.horizontal, Space.x4)
                        .padding(.vertical, Space.x2)
                        .background(Semantic.accent)
                        .cornerRadius(Radius.md)
                }
                .buttonStyle(.plain)
                .disabled(cannotContinue)
                .opacity(cannotContinue ? 0.5 : 1)

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

    private var keyBorderColor: Color {
        if model.onboardingBusy {
            return Semantic.border
        }
        return model.errorText != nil ? Semantic.destructive : Semantic.border
    }
}
