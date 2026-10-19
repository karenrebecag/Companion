import CompanionCore
import CompanionUIPro
import SwiftUI

/// Settings › Voz (Wave 16g): the ElevenLabs voice, with a sample next to it.
/// Speed, volume, turn detection, tone and echo cancellation stay in
/// `VoiceProfile.settings` with their current values; Incredible shows none
/// of them, and each was a knob only the builder understood.
struct SettingsVoiceSection: View {
    let preview: VoicePreview?
    /// 15f-6: only to know whether the ElevenLabs key is saved.
    var secrets: (any SecretStore)? = nil

    // HACK: VoiceID still names the voice the mouths receive, though none of
    // them reads it. Remove it with TTSFetching.fetch(_:voice:) once a mouth
    // needs a voice name; until then the preview passes the stored value.
    @State private var settings = VoiceProfile.settings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            if let error = preview?.errorText {
                Text(error)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
            }
            SettingsGroup(title: Localized.string("settings.voice.eleven.header")) {
                SettingsElevenLabsVoice(preview: preview, secrets: secrets, fallbackVoice: settings.voice)
                    .padding(Space.x4)
            }
        }
    }
}
