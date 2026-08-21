import CompanionCore
import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    private let preview: VoicePreview?
    @State private var ownerName = UserProfile.ownerName
    @State private var voice = VoiceProfile.stored
    @State private var shortcuts = ShortcutSet.load()

    public init(preview: VoicePreview? = nil) {
        self.preview = preview
    }

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

                    // Voz
                    VStack(alignment: .leading, spacing: Space.x3) {
                        Text("VOZ")
                            .typeEyebrow()
                        SettingsItem(
                            title: "Voz",
                            value: voice.displayName,
                            options: VoiceID.allCases.map { ($0, $0.displayName) }
                        ) { picked in
                            voice = picked
                            VoiceProfile.stored = picked
                        }
                        if let preview {
                            Button {
                                preview.play(voice)
                            } label: {
                                Text(preview.playing == voice
                                     ? "Sonando…" : "Escuchar muestra")
                                    .font(.uiLabel)
                            }
                            .disabled(preview.playing != nil)
                            if let error = preview.errorText {
                                Text(error)
                                    .font(.uiCaption)
                                    .foregroundStyle(Semantic.destructive)
                            }
                        }
                    }
                    .padding(.vertical, Space.x4)
                    .padding(.horizontal, Space.x4)

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

private struct SettingsItem<T: Hashable & CaseIterable>: View {
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
