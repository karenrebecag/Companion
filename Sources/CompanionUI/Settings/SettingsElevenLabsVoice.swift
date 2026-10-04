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
    // Pages also render in tests that never open the sheet.
    @Environment(SettingsSaveCenter.self) private var saves: SettingsSaveCenter?
    // Writes must persist with or without a sheet around the page.
    @State private var unhosted = SettingsSaveCenter()

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
        RadioCards(
            label: Localized.string("settings.voice.eleven.voice"),
            options: ElevenLabsVoiceCards.options(storedVoiceID: model.voiceID),
            selection: Binding(get: { model.shownChoice }, set: { choose($0) }))
        if model.shownChoice == .custom {
            HStack(alignment: .bottom, spacing: Space.x2) {
                AppField(
                    title: Localized.string("settings.voice.eleven.custom"),
                    placeholder: Localized.string("settings.voice.eleven.custom.placeholder"),
                    text: $model.customField,
                    error: model.errorText,
                    messagesInHint: true,
                    onSubmit: applyCustom)
                AppButton(
                    Localized.string("settings.voice.eleven.custom.apply"), kind: .ghost,
                    enabled: !model.customField.trimmingCharacters(in: .whitespaces).isEmpty,
                    action: applyCustom)
            }
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

    private func choose(_ choice: ElevenLabsVoiceChoice) {
        if case .preset(let id) = choice,
           let preset = ElevenLabsMouth.presets.first(where: { $0.id == id }) {
            (saves ?? unhosted).chooseElevenLabs(model, preset)
        } else {
            model.choose(choice)
        }
    }

    private func applyCustom() {
        (saves ?? unhosted).applyElevenLabsCustom(model)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .typeRole(.micro)
            .foregroundStyle(Semantic.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum ElevenLabsVoiceCards {
    /// One card per preset, then Custom, which shows a stored id in full so
    /// it can be told apart from the presets.
    static func options(storedVoiceID: String) -> [RadioCardOption<ElevenLabsVoiceChoice>] {
        let presets = ElevenLabsMouth.presets.map { preset in
            RadioCardOption(
                value: ElevenLabsVoiceChoice.preset(preset.id), label: preset.name,
                meta: preset.id == Config.defaultElevenLabsVoiceID
                    ? Localized.string("settings.voice.eleven.default") : nil)
        }
        let isPreset = ElevenLabsMouth.presets.contains { $0.id == storedVoiceID }
        return presets + [RadioCardOption(
            value: .custom, label: Localized.string("settings.voice.eleven.custom.label"),
            description: isPreset ? nil : storedVoiceID)]
    }
}
