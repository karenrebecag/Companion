import CompanionCore
import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    private let preview: VoicePreview?
    private let executors: ExecutorChoice?
    @State private var ownerName = UserProfile.ownerName
    @State private var voice = VoiceProfile.stored
    @State private var shortcuts = ShortcutSet.load()
    @State private var interfaceSounds = InterfaceSound.enabled

    public init(
        preview: VoicePreview? = nil,
        executors: ExecutorChoice? = nil,
        onLiveSpeedChange: ((Double) -> Void)? = nil,
        onAECRearm: (() -> Void)? = nil,
        echoFreeOutput: Bool = false,
        updates: UpdateState? = nil
    ) {
        self.preview = preview
        self.executors = executors
        self.onLiveSpeedChange = onLiveSpeedChange
        self.onAECRearm = onAECRearm
        self.echoFreeOutput = echoFreeOutput
        self.updates = updates
    }

    private let onLiveSpeedChange: ((Double) -> Void)?
    private let onAECRearm: (() -> Void)?
    private let echoFreeOutput: Bool
    private let updates: UpdateState?

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Ajustes")
                    .font(.uiTitle)
                    .foregroundStyle(Semantic.foreground)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.uiBody)
                        .foregroundStyle(Semantic.mutedForeground)
                }
                .buttonStyle(.plain)
            }
            .padding(Space.x4)
            .borderBottom()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.x6) {
                    // Apariencia
                    VStack(alignment: .leading, spacing: Space.x3) {
                        Text("APARIENCIA")
                            .typeEyebrow()

                        SettingsItem(
                            title: "Tipografía",
                            value: AppTypeface.stored.label,
                            options: AppTypeface.allCases.map { ($0, $0.label) }
                        ) { face in
                            AppTypeface.stored = face
                        }

                        SettingsItem(
                            title: "Color de acento",
                            value: Highlight.stored.label,
                            options: Highlight.allCases.map { ($0, $0.label) }
                        ) { highlight in
                            Highlight.stored = highlight
                        }
                    }
                    .padding(.vertical, Space.x4)
                    .padding(.horizontal, Space.x4)

                    Divider()
                        .foregroundStyle(Semantic.border)

                    // Perfil
                    VStack(alignment: .leading, spacing: Space.x3) {
                        Text("PERFIL")
                            .typeEyebrow()
                        VStack(alignment: .leading, spacing: Space.x2) {
                            Text("Cómo te llamo")
                                .font(.uiLabel)
                                .foregroundStyle(Semantic.foreground)
                            TextField("Tu nombre", text: $ownerName)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: ownerName) { _, name in
                                    UserProfile.ownerName = name
                                }
                        }
                    }
                    .padding(.vertical, Space.x4)
                    .padding(.horizontal, Space.x4)

                    Divider()
                        .foregroundStyle(Semantic.border)

                    // Voz — seccion completa en su propio archivo
                    SettingsVoiceSection(
                        preview: preview,
                        onLiveSpeedChange: onLiveSpeedChange,
                        onAECRearm: onAECRearm,
                        echoFreeOutput: echoFreeOutput)

                    if let executors, executors.isMeaningful {
                        Divider()
                            .foregroundStyle(Semantic.border)

                        VStack(alignment: .leading, spacing: Space.x3) {
                            Text("ESPECIALISTA")
                                .typeEyebrow()
                            SettingsItem(
                                title: "Quién trabaja los encargos",
                                value: executors.available
                                    .first { $0.id == executors.selected }?
                                    .title ?? "Nativo",
                                options: executors.available.map { ($0.id, $0.title) }
                            ) { id in
                                executors.selected = id
                            }
                        }
                        .padding(.vertical, Space.x4)
                        .padding(.horizontal, Space.x4)
                    }

                    Divider()
                        .foregroundStyle(Semantic.border)

                    // Sistema
                    VStack(alignment: .leading, spacing: Space.x3) {
                        Text("SISTEMA")
                            .typeEyebrow()

                        VStack(alignment: .leading, spacing: Space.x2) {
                            Text("Versión")
                                .font(.uiLabel)
                                .foregroundStyle(Semantic.foreground)
                            Text(appVersion)
                                .font(.uiCaption)
                                .foregroundStyle(Semantic.mutedForeground)
                            if let updates {
                                if let available = updates.available {
                                    Link(
                                        "Ver la versión \(available.tag)",
                                        destination: available.pageURL)
                                        .font(.uiLabel)
                                        .foregroundStyle(Semantic.accent)
                                } else {
                                    Button(updates.checking
                                           ? "Buscando…" : "Buscar actualización") {
                                        updates.requestCheck()
                                    }
                                    .font(.uiCaption)
                                    .disabled(updates.checking)
                                }
                            }
                        }

                        Toggle("Sonidos de interfaz", isOn: $interfaceSounds)
                            .font(.uiLabel)
                            .foregroundStyle(Semantic.foreground)
                            .onChange(of: interfaceSounds) { _, on in
                                InterfaceSound.enabled = on
                            }
                    }
                    .padding(.vertical, Space.x4)
                    .padding(.horizontal, Space.x4)

                    Divider()
                        .foregroundStyle(Semantic.border)

                    // Atajos de teclado
                    VStack(alignment: .leading, spacing: Space.x3) {
                        Text("ATAJOS")
                            .typeEyebrow()

                        if !shortcuts.shortcuts.isEmpty {
                            VStack(alignment: .leading, spacing: Space.x2) {
                                ForEach(Array(shortcuts.shortcuts.enumerated()), id: \.offset) { _, shortcut in
                                    shortcutRow(shortcut)
                                }
                            }
                        }

                        if !shortcuts.hasConflicts().isEmpty {
                            Text("Hay conflictos entre atajos")
                                .font(.uiCaption)
                                .foregroundStyle(Semantic.destructive)
                        }
                    }
                    .padding(.vertical, Space.x4)
                    .padding(.horizontal, Space.x4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Semantic.background)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "desconocida"
    }

    private func shortcutRow(_ shortcut: Shortcut) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack {
                Text(shortcut.action.label)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                Spacer()
                Text(shortcut.displayKey())
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
    }
}

// MARK: - Settings Item with Picker

// Options arrive as a parameter, so requiring CaseIterable only shut out
// runtime-built lists like the detected executors. Internal, not private:
// SettingsVoiceSection lives in its own file and reuses it.
struct SettingsItem<T: Hashable>: View {
    let title: String
    let value: String
    let options: [(T, String)]
    let onChange: (T) -> Void

    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack {
                Text(title)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                Spacer()
                Menu {
                    ForEach(options, id: \.0) { option, label in
                        Button(action: { onChange(option) }) {
                            HStack {
                                Text(label)
                                if label == value {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: Space.x2) {
                        Text(value)
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.accentText)
                        Image(systemName: "chevron.down")
                            .font(.uiMicro)
                            .foregroundStyle(Semantic.mutedForeground)
                    }
                    .padding(.horizontal, Space.x3)
                    .padding(.vertical, Space.x2)
                    .background(Semantic.muted)
                    .cornerRadius(Radius.md)
                }
            }
        }
    }
}

// MARK: - Border Bottom Modifier

private extension View {
    func borderBottom() -> some View {
        VStack(spacing: 0) {
            self
            Divider()
                .foregroundStyle(Semantic.border)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SettingsView()
        .frame(width: 400, height: 500)
}
#endif
