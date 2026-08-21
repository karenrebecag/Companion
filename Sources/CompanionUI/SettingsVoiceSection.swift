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
            Text("VOZ")
                .typeEyebrow()

            SettingsItem(
                title: "Voz",
                value: settings.voice.displayName,
                options: VoiceID.allCases.map { ($0, $0.displayName) }
            ) { picked in
                update { $0.voice = picked }
            }
            previewControls
            Text("La voz, el tono y el fin de turno aplican en tu próxima "
                 + "conversación. La velocidad y el volumen cambian al instante.")
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            slider(
                "Velocidad", value: settings.speed,
                range: 0.25 ... 1.5, format: "%.2fx"
            ) { speed in
                update { $0.speed = speed }
                // The one knob the server accepts mid-session.
                onLiveSpeedChange?(speed)
            }
            slider(
                "Volumen", value: settings.volume,
                range: 0 ... 1, format: "%.0f%%", scale: 100
            ) { volume in
                update { $0.volume = volume }
                onLiveVolumeChange?(volume)
            }

            DisclosureGroup("Avanzado") {
                VStack(alignment: .leading, spacing: Space.x3) {
                    SettingsItem(
                        title: "Fin de turno",
                        value: TurnCriterion(settings.turnDetection).label,
                        options: TurnCriterion.allCases.map { ($0, $0.label) }
                    ) { criterion in
                        update { $0.turnDetection = criterion.applied(to: settings.turnDetection) }
                    }
                    criterionDetail

                    AppField(
                        title: "Tono",
                        placeholder: "p. ej. cálida y directa",
                        text: toneBinding)

                    Toggle(isOn: aecBinding) {
                        VStack(alignment: .leading, spacing: Space.x1) {
                            Text("Cancelación de eco")
                                .font(.uiLabel)
                                .foregroundStyle(Semantic.foreground)
                            Text(echoFreeOutput
                                 ? "Con audífonos no hace falta: ya puedes interrumpir hablando."
                                 : "En algunos equipos la de Apple no arranca; si falla, se desactiva sola.")
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
                preview.playing == settings.voice ? "Sonando…" : "Escuchar muestra",
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
                "Paciencia", value: Double(ms),
                range: 200 ... 1500, format: "%.0f ms"
            ) { value in
                update { $0.turnDetection = .serverVAD(silenceMs: Int(value)) }
            }
            Text("Cede el turno cuando llevas este silencio sin hablar.")
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
        case .semanticVAD(let eagerness):
            SettingsItem(
                title: "Avidez",
                value: eagerness.label,
                options: Eagerness.allCases.map { ($0, $0.label) }
            ) { picked in
                update { $0.turnDetection = .semanticVAD(eagerness: picked) }
            }
            Text("Espera a que la frase suene completa antes de responder.")
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
        case .silence: "Silencio"
        case .meaning: "Sentido"
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
        case .low: "Baja"
        case .auto: "Auto"
        case .high: "Alta"
        }
    }
}
