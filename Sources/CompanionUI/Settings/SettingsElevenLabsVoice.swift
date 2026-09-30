import CompanionCore
import SwiftUI

/// Wave 15f-6: the ElevenLabs voice in Settings › Voz. Without a key the
/// picker would choose a voice nothing speaks with, so it hides and one
/// line says which voice is used instead.
struct SettingsElevenLabsVoice: View {
    let preview: VoicePreview?
    let secrets: (any SecretStore)?
    /// The OpenAI voice the mouth falls back to, so the sample does too.
    let fallbackVoice: VoiceID

    @State private var model = ElevenLabsVoiceModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            if model.hasKey {
                picker
            } else {
                caption(Localized.string("settings.voice.eleven.nokey"))
            }
        }
        .onAppear {
            model.secrets = secrets
            model.refresh()
        }
    }

    @ViewBuilder private var picker: some View {
        caption(Localized.string("settings.voice.eleven.blurb"))
        SettingsItem(
            title: Localized.string("settings.voice.eleven.voice"),
            value: model.selectedPreset?.name
                ?? Localized.string("settings.voice.eleven.custom.label"),
            options: ElevenLabsMouth.presets.map { ($0, $0.name) }
        ) { preset in
            model.select(preset)
        }
        HStack(alignment: .bottom, spacing: Space.x2) {
            AppField(
                title: Localized.string("settings.voice.eleven.custom"),
                placeholder: Localized.string("settings.voice.eleven.custom.placeholder"),
                text: $model.customField,
                onSubmit: { model.applyCustom() })
            AppButton(
                Localized.string("settings.voice.eleven.custom.apply"), kind: .ghost,
                enabled: !model.customField.trimmingCharacters(in: .whitespaces).isEmpty,
                action: { model.applyCustom() })
        }
        if let error = model.errorText {
            Text(error)
                .font(.uiCaption)
                .foregroundStyle(Semantic.destructive)
        }
        if let preview {
            AppButton(
                preview.playingMouth
                    ? Localized.string("settings.voice.preview.playing")
                    : Localized.string("settings.voice.preview.listen"),
                kind: .secondary,
                enabled: !preview.isBusy
            ) {
                preview.playMouth(fallbackVoice)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.uiCaption)
            .foregroundStyle(Semantic.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }
}
