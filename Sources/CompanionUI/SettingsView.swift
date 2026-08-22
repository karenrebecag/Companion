import AppKit
import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

public enum SettingsTab: String, CaseIterable, Equatable {
    case you
    case voice
    case app

    /// The raw value is an identifier (it is persisted and compared); what
    /// the tab bar shows is this, which follows the language.
    public var title: String {
        Localized.string("settings.tab.\(rawValue)")
    }

    public var symbol: String {
        switch self {
        case .you: "person.crop.circle"
        case .voice: "waveform"
        case .app: "square.grid.2x2"
        }
    }
}

public enum SettingsOverlayMetrics {
    public static let maxSide: CGFloat = 560
    public static let cardHeight: CGFloat = 68
    public static let avatar: CGFloat = Space.x8 + Space.x1
    public static let stepHit: CGFloat = Space.x8
}

public struct SettingsView: View {
    private let preview: VoicePreview?
    var chat: ChatViewModel?
    let onClose: () -> Void
    @Binding var tab: SettingsTab
    @State private var ownerName = UserProfile.ownerName
    @State private var about = UserProfile.about
    @State private var instructions = UserProfile.instructions
    @State private var interfaceSounds = InterfaceSound.enabled
    @State private var fontDelta = TypeScale.delta
    @State private var avatar = UserProfile.avatarImage
    @State private var confirmPurge = false
    @State private var storageLabel = Localized.string("settings.storage.empty")
    @Environment(DropdownHost.self) private var dropdowns

    public init(
        preview: VoicePreview? = nil,
        chat: ChatViewModel? = nil,
        onLiveSpeedChange: ((Double) -> Void)? = nil,
        onLiveVolumeChange: ((Double) -> Void)? = nil,
        onAECRearm: (() -> Void)? = nil,
        echoFreeOutput: Bool = false,
        updates: UpdateState? = nil,
        tab: Binding<SettingsTab> = .constant(.you),
        onClose: @escaping () -> Void = {}
    ) {
        self.preview = preview
        self.chat = chat
        self.onLiveSpeedChange = onLiveSpeedChange
        self.onLiveVolumeChange = onLiveVolumeChange
        self.onAECRearm = onAECRearm
        self.echoFreeOutput = echoFreeOutput
        self.updates = updates
        self._tab = tab
        self.onClose = onClose
    }

    private let onLiveSpeedChange: ((Double) -> Void)?
    private let onLiveVolumeChange: ((Double) -> Void)?
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
                    case .you: youPane
                    case .voice: voicePane
                    case .app: appPane
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
        .overlay { purgeConfirm }
        .dropdownPortal(host: dropdowns)
        .onDisappear { dropdowns.dismiss() }
        .onAppear { storageLabel = chat?.attachmentsStorageLabel
                ?? Localized.string("settings.storage.empty") }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionProfileDidChange)
        ) { _ in
            avatar = UserProfile.avatarImage
        }
    }

    private var header: some View {
        HStack {
            Text(Localized.string("settings.title"))
                .font(.uiTitle)
                .foregroundStyle(Semantic.foreground)
            Spacer()
            RoundIconButton(
                icon: .cross,
                foreground: Semantic.foreground,
                background: Semantic.surface,
                help: Localized.string("settings.close")
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
        HStack(spacing: Space.x1) {
            ForEach(SettingsTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.springSelect) {
                        tab = t
                        dropdowns.dismiss()
                    }
                } label: {
                    VStack(spacing: Space.x1) {
                        Image(systemName: t.symbol)
                            .font(.uiCaption)
                        Text(t.title)
                            .font(.uiCaption)
                    }
                    .foregroundStyle(
                        tab == t ? Semantic.foreground : Semantic.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.x2)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(Semantic.surface.opacity(tab == t ? 1 : 0))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(
                                tab == t ? Semantic.border : Color.clear,
                                lineWidth: Stroke.hairline)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(.horizontal, Space.x5)
        .padding(.bottom, Space.x3)
    }

    // MARK: - Tú

    private var youPane: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            Text(Localized.string("settings.you.header"))
                .typeEyebrow()
            photoRow
            Text(Localized.string("settings.you.blurb"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            AppField(
                title: Localized.string("settings.you.name"),
                placeholder: Localized.string("settings.you.name.placeholder"),
                text: $ownerName)
            SettingsMultiline(
                title: Localized.string("settings.you.about"),
                placeholder: Localized.string("settings.you.about.placeholder"),
                text: $about)
            SettingsMultiline(
                title: Localized.string("settings.you.instructions"),
                placeholder: Localized.string("settings.you.instructions.placeholder"),
                text: $instructions)
        }
        .onChange(of: ownerName) { persistProfile() }
        .onChange(of: about) { persistProfile() }
        .onChange(of: instructions) { persistProfile() }
    }

    private var photoRow: some View {
        SettingsLine(
            title: Localized.string("settings.you.photo"),
            subtitle: Localized.string("settings.you.photo.subtitle")
        ) {
            HStack(spacing: Space.x2) {
                avatarThumb
                Button(action: pickAvatar) {
                    Image(systemName: "pencil")
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.foreground)
                        .frame(width: Space.x6, height: Space.x6)
                        .background(Circle().fill(Semantic.surface))
                        .overlay(Circle().stroke(Semantic.border, lineWidth: Stroke.hairline))
                }
                .buttonStyle(PressableStyle())
                .help(Localized.string("settings.you.photo.change"))
                .accessibilityLabel(Localized.string("settings.you.photo.change"))
            }
        }
    }

    private var avatarThumb: some View {
        Group {
            if let avatar {
                Image(nsImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.uiTitle)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .frame(
            width: SettingsOverlayMetrics.avatar,
            height: SettingsOverlayMetrics.avatar)
        .clipShape(Circle())
        .overlay(Circle().stroke(Semantic.border, lineWidth: Stroke.hairline))
    }

    // MARK: - Voz

    private var voicePane: some View {
        SettingsVoiceSection(
            preview: preview,
            onLiveSpeedChange: onLiveSpeedChange,
            onLiveVolumeChange: onLiveVolumeChange,
            onAECRearm: onAECRearm,
            echoFreeOutput: echoFreeOutput)
    }

    // MARK: - App

    private var appPane: some View {
        SettingsAppPane(
            chat: chat,
            updates: updates,
            fontDelta: $fontDelta,
            interfaceSounds: $interfaceSounds,
            storageLabel: $storageLabel,
            confirmPurge: $confirmPurge)
    }

    @ViewBuilder
    private var purgeConfirm: some View {
        if confirmPurge {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Semantic.scrim)
                    .onTapGesture { confirmPurge = false }
                VStack(alignment: .leading, spacing: Space.x3) {
                    Text(Localized.string("settings.purge.title"))
                        .font(.uiSubtitle)
                        .foregroundStyle(Semantic.foreground)
                    Text(String(
                        format: Localized.string("settings.purge.blurb"),
                        storageLabel))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.x2) {
                        Spacer()
                        AppButton(Localized.string("settings.purge.cancel"), kind: .secondary) { confirmPurge = false }
                        AppButton(Localized.string("settings.purge.confirm"), kind: .destructive) {
                            chat?.purgeStoredAttachments()
                            storageLabel = chat?.attachmentsStorageLabel
                ?? Localized.string("settings.storage.empty")
                            confirmPurge = false
                        }
                    }
                }
                .padding(Space.x5)
                .frame(maxWidth: 400)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .fill(Semantic.surfaceOverlay)
                        .elevation(.sheet)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .stroke(Semantic.border, lineWidth: Stroke.hairline)
                )
            }
        }
    }

    // Sin notificación por tecla: la de perfil solo la manda el avatar,
    // que es lo único que otros observan; el texto se lee por petición.
    private func persistProfile() {
        UserProfile.ownerName = ownerName
        UserProfile.about = about
        UserProfile.instructions = instructions
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if UserProfile.setAvatar(from: url) {
                avatar = UserProfile.avatarImage
            }
        }
    }

}

#if DEBUG
#Preview {
    SettingsView(onClose: {})
        .environment(DropdownHost())
        .frame(width: 400, height: 500)
}
#endif
