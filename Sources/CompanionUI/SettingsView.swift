import CompanionCore
import SwiftUI

public enum SettingsTab: String, CaseIterable, Equatable {
    case appearance = "Apariencia"
    case profile = "Perfil"
    case voice = "Voz"
    case system = "Sistema"
    case keyboard = "Atajos"

    var symbol: String {
        switch self {
        case .appearance: "paintbrush"
        case .profile: "person.crop.circle"
        case .voice: "waveform"
        case .system: "gearshape"
        case .keyboard: "keyboard"
        }
    }
}

public enum SettingsOverlayMetrics {
    public static let maxSide: CGFloat = 560
}

public struct SettingsView: View {
    private let preview: VoicePreview?
    private let executors: ExecutorChoice?
    let onClose: () -> Void
    @State private var ownerName = UserProfile.ownerName
    @State private var shortcuts = ShortcutSet.load()
    @State private var interfaceSounds = InterfaceSound.enabled
    @State private var tab: SettingsTab = .appearance
    @Environment(DropdownHost.self) private var dropdowns

    public init(
        preview: VoicePreview? = nil,
        executors: ExecutorChoice? = nil,
        onLiveSpeedChange: ((Double) -> Void)? = nil,
        onAECRearm: (() -> Void)? = nil,
        echoFreeOutput: Bool = false,
        updates: UpdateState? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.preview = preview
        self.executors = executors
        self.onLiveSpeedChange = onLiveSpeedChange
        self.onAECRearm = onAECRearm
        self.echoFreeOutput = echoFreeOutput
        self.updates = updates
        self.onClose = onClose
    }

    private let onLiveSpeedChange: ((Double) -> Void)?
    private let onAECRearm: (() -> Void)?
    private let echoFreeOutput: Bool
    private let updates: UpdateState?

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            header
            tabs
            Divider().overlay(Semantic.border)
            ScrollView {
                Group {
                    switch tab {
                    case .appearance: appearancePane
                    case .profile: profilePane
                    case .voice: voicePane
                    case .system: systemPane
                    case .keyboard: keyboardPane
                    }
                }
                .padding(Space.x5)
                .id(tab)
                .transition(.modeSwap)
            }
            .scrollIndicators(.hidden)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(Semantic.surfaceOverlay)
                .elevation(.sheet)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(Semantic.border, lineWidth: Stroke.hairline)
        )
        .overlay {
            if dropdowns.session.isOpen, case .settingsPick = dropdowns.menu {
                Color.black.opacity(0.001)
                    .onTapGesture {
                        withAnimation(.springSheet) { dropdowns.dismiss() }
                    }
            }
        }
        .dropdownPortal(host: dropdowns)
        .onDisappear { dropdowns.dismiss() }
    }

    private var header: some View {
        HStack {
            Text("Ajustes")
                .font(.uiTitle)
                .foregroundStyle(Semantic.foreground)
            Spacer()
            RoundIconButton(
                icon: .cross,
                foreground: Semantic.foreground,
                background: Semantic.surface,
                help: "Cerrar"
            ) {
                dropdowns.dismiss()
                withAnimation(.springSheet) { onClose() }
            }
        }
        .padding(.horizontal, Space.x5)
        .padding(.top, Space.x5)
        .padding(.bottom, Space.x3)
    }

    private var tabs: some View {
        HStack(spacing: Space.x2) {
            ForEach(SettingsTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.springSelect) {
                        tab = t
                        dropdowns.dismiss()
                    }
                } label: {
                    HStack(spacing: Space.x1 + Space.x1 / 2) {
                        Image(systemName: t.symbol)
                            .font(.uiCaption)
                        Text(t.rawValue)
                            .font(.uiCaption)
                    }
                    .foregroundStyle(
                        tab == t ? Semantic.foreground : Semantic.mutedForeground)
                    .padding(.horizontal, Space.x2 + Space.x1 / 2)
                    .padding(.vertical, Space.x1 + Space.x1 / 2)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(Semantic.surface.opacity(tab == t ? 1 : 0))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Space.x5)
        .padding(.bottom, Space.x3)
    }

    private var appearancePane: some View {
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
                options: Highlight.allCases.map { ($0, $0.label) },
                rainbow: { $0 == .standard },
                swatch: { $0 == .standard ? nil : $0.swatch }
            ) { highlight in
                Highlight.stored = highlight
            }
        }
    }

    private var profilePane: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text("PERFIL")
                .typeEyebrow()
            AppField(
                title: "Cómo te llamo",
                placeholder: "Tu nombre",
                text: $ownerName)
            .onChange(of: ownerName) { _, name in
                UserProfile.ownerName = name
            }
        }
    }

    private var voicePane: some View {
        VStack(alignment: .leading, spacing: Space.x6) {
            SettingsVoiceSection(
                preview: preview,
                onLiveSpeedChange: onLiveSpeedChange,
                onAECRearm: onAECRearm,
                echoFreeOutput: echoFreeOutput)
            if let executors, executors.isMeaningful {
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
            }
        }
    }

    private var systemPane: some View {
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
                        AppButton(
                            updates.checking
                                ? "Buscando…" : "Buscar actualización",
                            kind: .ghost,
                            enabled: !updates.checking
                        ) {
                            updates.requestCheck()
                        }
                    }
                }
            }
            Toggle("Sonidos de interfaz", isOn: $interfaceSounds)
                .font(.uiLabel)
                .foregroundStyle(Semantic.foreground)
                .tint(Semantic.accent)
                .onChange(of: interfaceSounds) { _, on in
                    InterfaceSound.enabled = on
                }
        }
    }

    private var keyboardPane: some View {
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

// MARK: - Border Bottom Modifier

private extension View {
    func borderBottom() -> some View {
        VStack(spacing: Space.none) {
            self
            Divider()
                .foregroundStyle(Semantic.border)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SettingsView(onClose: {})
        .environment(DropdownHost())
        .frame(width: 400, height: 500)
}
#endif
