import CompanionCore
import SwiftUI

/// Settings › Voz (Wave 16g): which voice, with a sample next to it.
/// Speed, volume, turn detection, tone and echo cancellation stay in
/// `VoiceProfile.settings` with their current values; Incredible shows none
/// of them, and each was a knob only the builder understood.
struct SettingsVoiceSection: View {
    let preview: VoicePreview?
    /// 15f-6: only to know whether the ElevenLabs key is saved.
    var secrets: (any SecretStore)? = nil

    @State private var settings = VoiceProfile.settings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsPageHeader(title: SettingsTab.voice.title, blurb: Localized.string("settings.voice.blurb"))
            SettingsCard {
                SettingsRow(title: Localized.string("settings.voice.voice"), key: "settings.voice.voice") {
                    HStack(spacing: Space.x2) {
                        previewPill
                        SettingsItem(
                            title: "",
                            value: settings.voice.displayName,
                            options: VoiceID.allCases.map { ($0, $0.displayName) },
                            id: "settings.voice.voice"
                        ) { picked in
                            update { $0.voice = picked }
                        }
                    }
                }
            }
            if let error = preview?.errorText {
                Text(error)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
            }
            SettingsCard(label: Localized.string("settings.voice.eleven.header")) {
                SettingsElevenLabsVoice(preview: preview, secrets: secrets, fallbackVoice: settings.voice)
                    .padding(Space.x4)
            }
        }
    }

    @ViewBuilder private var previewPill: some View {
        if let preview {
            SettingsPill(
                title: preview.playing == settings.voice
                    ? Localized.string("settings.voice.preview.playing")
                    : Localized.string("settings.voice.preview.listen"),
                symbol: "speaker.wave.2",
                enabled: !preview.isBusy
            ) {
                preview.play(settings.voice)
            }
        }
    }

    private func update(_ mutate: (inout VoiceSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        VoiceProfile.settings = copy
    }
}
