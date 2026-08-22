import CompanionCore
import SwiftUI

/// The full voice pane: what the prototype let you tune and this rebuild
/// finally exposes. Every control writes VoiceProfile.settings, which the
/// config provider reads at the next session open; speed also applies hot.
struct SettingsVoiceSection: View {
    let preview: VoicePreview?
    /// Non-nil while a session can take a live speed update.
    let onLiveSpeedChange: ((Double) -> Void)?
    /// Volume applies to the local player at once, session or not.
    let onLiveVolumeChange: ((Double) -> Void)?
    /// Clears the persisted VPIO veto; lives in Services, so the composition
    /// hands it in (UI cannot import Services by layering).
    let onAECRearm: (() -> Void)?
    /// With an echo-free output there is no echo to cancel: the toggle locks
    /// with an explanation instead of offering a knob that does nothing.
    let echoFreeOutput: Bool

    @State private var settings = VoiceProfile.settings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(Localized.string("settings.voice.header"))
                .typeEyebrow()

            SettingsItem(
                title: Localized.string("settings.voice.voice"),
                value: settings.voice.displayName,
                options: VoiceID.allCases.map { ($0, $0.displayName) }
            ) { picked in
                update { $0.voice = picked }
            }
            previewControls
            Text(Localized.string("settings.voice.blurb"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            slider(
                Localized.string("settings.voice.speed"), value: settings.speed,
                range: 0.25 ... 1.5, format: "%.2fx"
            ) { speed in
                update { $0.speed = speed }
                // The one knob the server accepts mid-session.
                onLiveSpeedChange?(speed)
            }
            slider(
                Localized.string("settings.voice.volume"), value: settings.volume,
                range: 0 ... 1, format: "%.0f%%", scale: 100
            ) { volume in
                update { $0.volume = volume }
                onLiveVolumeChange?(volume)
            }

            DisclosureGroup(Localized.string("settings.voice.advanced")) {
                VStack(alignment: .leading, spacing: Space.x3) {
                    SettingsItem(
                        title: Localized.string("settings.voice.turnEnd"),
                        value: TurnCriterion(settings.turnDetection).label,
                        options: TurnCriterion.allCases.map { ($0, $0.label) }
                    ) { criterion in
                        update { $0.turnDetection = criterion.applied(to: settings.turnDetection) }
                    }
                    criterionDetail

                    AppField(
                        title: Localized.string("settings.voice.tone"),
                        placeholder: Localized.string("settings.voice.tone.placeholder"),
                        text: toneBinding)

                    Toggle(isOn: aecBinding) {
                        VStack(alignment: .leading, spacing: Space.x1) {
                            Text(Localized.string("settings.voice.aec"))
                                .font(.uiLabel)
                                .foregroundStyle(Semantic.foreground)
                            Text(echoFreeOutput
                                 ? Localized.string("settings.voice.aec.headphones")
                                 : Localized.string("settings.voice.aec.warning"))
                                .font(.uiCaption)
                                .foregroundStyle(Semantic.mutedForeground)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(Semantic.accent)
                    .disabled(echoFreeOutput)
                }
                .padding(.top, Space.x3)
            }
            .font(.uiLabel)
            .foregroundStyle(Semantic.mutedForeground)
            .tint(Semantic.accent)
        }
        .padding(.vertical, Space.x2)
    }

    // MARK: - Subviews

    @ViewBuilder private var previewControls: some View {
        if let preview {
            AppButton(
                preview.playing == settings.voice ? Localized.string("settings.voice.preview.playing") : Localized.string("settings.voice.preview.listen"),
                kind: .secondary,
                enabled: preview.playing == nil
            ) {
                preview.play(settings.voice)
            }
            if let error = preview.errorText {
                Text(error)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
            }
        }
    }

    @ViewBuilder private var criterionDetail: some View {
        switch settings.turnDetection {
        case .serverVAD(let ms):
            slider(
                Localized.string("settings.voice.patience"), value: Double(ms),
                range: 200 ... 1500, format: "%.0f ms"
            ) { value in
                update { $0.turnDetection = .serverVAD(silenceMs: Int(value)) }
            }
            Text(Localized.string("settings.voice.patience.blurb"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
        case .semanticVAD(let eagerness):
            SettingsItem(
                title: Localized.string("settings.voice.eagerness"),
                value: eagerness.label,
                options: Eagerness.allCases.map { ($0, $0.label) }
            ) { picked in
                update { $0.turnDetection = .semanticVAD(eagerness: picked) }
            }
            Text(Localized.string("settings.voice.eagerness.blurb"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
        }
    }

    private func slider(
        _ title: String, value: Double,
        range: ClosedRange<Double>, format: String, scale: Double = 1,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            HStack {
                Text(title)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                Spacer()
                Text(String(format: format, value * scale))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: range)
            .tint(Semantic.accent)
        }
    }

    // MARK: - Bindings

    private var toneBinding: Binding<String> {
        Binding(
            get: { settings.tone },
            set: { tone in update { $0.tone = tone } })
    }

    private var aecBinding: Binding<Bool> {
        Binding(
            get: { settings.echoCancellation },
            set: { enabled in
                update { $0.echoCancellation = enabled }
                if enabled {
                    // Re-arm: one fresh VPIO attempt next session, like the
                    // prototype's aecVetoed toggle (ledger, Audio/AEC).
                    onAECRearm?()
                }
            })
    }

    private func update(_ mutate: (inout VoiceSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        VoiceProfile.settings = copy
    }
}

/// Turn criterion as the user sees it; maps onto TurnDetection keeping the
/// detail (patience / eagerness) each mode remembers.
enum TurnCriterion: CaseIterable, Hashable {
    case silence, meaning

    init(_ detection: TurnDetection) {
        if case .serverVAD = detection { self = .silence } else { self = .meaning }
    }

    var label: String {
        switch self {
        case .silence: Localized.string("settings.voice.turnEnd.silence")
        case .meaning: Localized.string("settings.voice.turnEnd.meaning")
        }
    }

    func applied(to current: TurnDetection) -> TurnDetection {
        switch (self, current) {
        case (.silence, .serverVAD), (.meaning, .semanticVAD): current
        case (.silence, _): .serverVAD(silenceMs: 700)
        case (.meaning, _): .semanticVAD(eagerness: .auto)
        }
    }
}

extension Eagerness {
    var label: String {
        switch self {
        case .low: Localized.string("settings.voice.eagerness.low")
        case .auto: "Auto"
        case .high: Localized.string("settings.voice.eagerness.high")
        }
    }
}
