import CompanionCore
import SwiftUI

public enum InteractionMode: String, Sendable, CaseIterable, Equatable {
    case voice, text
}

public enum HeaderMetrics {
    public static let topClearance: CGFloat = Space.x1 * 10
    public static let avatar: CGFloat = IconSize.hero
}

public enum HistoryOverlayMetrics {
    public static let maxSide: CGFloat = SettingsOverlayMetrics.maxSide
    public static let minWidth: CGFloat = 300
}

public struct HeaderView: View {
    var chat: ChatViewModel
    var voice: VoiceViewModel
    var executors: ExecutorChoice?
    @Binding var mode: InteractionMode
    var onSettings: () -> Void
    var onFolder: () -> Void

    @Environment(DropdownHost.self) private var host
    @Namespace private var modeNS
    @State private var avatarImage = UserProfile.avatarImage

    public init(
        chat: ChatViewModel,
        voice: VoiceViewModel,
        executors: ExecutorChoice?,
        mode: Binding<InteractionMode>,
        onSettings: @escaping () -> Void,
        onFolder: @escaping () -> Void = {}
    ) {
        self.chat = chat
        self.voice = voice
        self.executors = executors
        self._mode = mode
        self.onSettings = onSettings
        self.onFolder = onFolder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.gapXS) {
            Text("Companion")
                .font(.uiLogo)
                .tracking(Tracking.tighter, at: TypeSize.display)
                .foregroundStyle(Semantic.foreground)
            HStack(spacing: Space.x2) {
                choiceMenu
                modeToggle
                Spacer()
                HoverIconButton(
                    symbol: "clock.arrow.circlepath",
                    help: "Conversaciones"
                ) {
                    withAnimation(.springSheet) { host.toggle(.history) }
                }
                HoverIconButton(icon: .folder, help: "Carpeta de trabajo") {
                    onFolder()
                }
                avatar
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.top, HeaderMetrics.topClearance)
        .onReceive(
            NotificationCenter.default.publisher(for: .companionProfileDidChange)
        ) { _ in
            avatarImage = UserProfile.avatarImage
        }
    }

    private var choiceTitle: String {
        guard let executors else { return ExecutorCatalog.native.title }
        return executors.available.first { $0.id == executors.selected }?.title
            ?? ExecutorCatalog.native.title
    }

    private var choiceMenu: some View {
        Button {
            withAnimation(.springSheet) { host.toggle(.choice) }
        } label: {
            HStack(spacing: Space.x1) {
                Text(choiceTitle)
                    .font(Fonts.mono(11.5))
                Image(systemName: "chevron.down")
                    .font(Fonts.sans(8))
                    .rotationEffect(.degrees(host.menu == .choice ? 180 : 0))
            }
            .foregroundStyle(Semantic.mutedForeground)
            .padding(.horizontal, Space.x2 + Space.x1 / 2)
            .padding(.vertical, Space.x1 + Space.x1 / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .hoverChip()
    }

    private var modeToggle: some View {
        HStack(spacing: Space.x1 / 2) {
            modeSegment(.voice, "waveform", "Modo voz")
            modeSegment(.text, "keyboard", "Modo texto")
        }
        .padding(Space.x1 / 2)
        .background(Capsule().fill(Semantic.surface.opacity(0.55)))
        .overlay(Capsule().stroke(Semantic.border, lineWidth: Stroke.hairline).opacity(0.5))
    }

    private func modeSegment(
        _ m: InteractionMode, _ symbol: String, _ help: String
    ) -> some View {
        Button {
            withAnimation(.springSelect) { mode = m }
        } label: {
            Image(systemName: symbol)
                .font(.uiCaption)
                .foregroundStyle(
                    mode == m ? Semantic.foreground : Semantic.mutedForeground)
                .frame(
                    width: Space.x6 + Space.x1 / 2,
                    height: Space.x5 + Space.x1 / 2)
                .background {
                    if mode == m {
                        Capsule().fill(Semantic.background)
                            .elevationChip()
                            .matchedGeometryEffect(id: "modeSel", in: modeNS)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }

    private var avatar: some View {
        Button(action: onSettings) {
            Group {
                if let avatarImage {
                    Image(nsImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.uiTitle)
                        .foregroundStyle(Semantic.mutedForeground)
                }
            }
            .frame(width: HeaderMetrics.avatar, height: HeaderMetrics.avatar)
            .clipShape(Circle())
            .overlay(Circle().stroke(Semantic.border, lineWidth: Stroke.hairline))
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help("Ajustes")
        .accessibilityLabel("Ajustes")
    }
}

struct ChoiceDropdown: View {
    var executors: ExecutorChoice?
    var host: DropdownHost

    var body: some View {
        let rows = executors?.available ?? [ExecutorCatalog.native]
        DropdownPanel {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, d in
                DropdownRow(
                    title: d.title,
                    selected: d.id == (executors?.selected ?? .native),
                    index: i
                ) {
                    executors?.selected = d.id
                    withAnimation(.springSheet) { host.dismiss() }
                }
            }
        }
    }
}

struct HistoryOverlay: View {
    var chat: ChatViewModel
    var voice: VoiceViewModel
    var host: DropdownHost

    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            header
            Divider().overlay(Semantic.border)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x1) {
                    DropdownRow(
                        title: "Nueva conversación",
                        symbol: "square.and.pencil",
                        index: 0,
                        titleMaxWidth: .infinity
                    ) {
                        voice.hangUp()
                        chat.newConversation()
                        withAnimation(.springSheet) { host.dismiss() }
                    }
                    if chat.recents.isEmpty {
                        Text("Todavía no hay conversaciones")
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.mutedForeground)
                            .padding(.horizontal, Space.x3)
                            .padding(.vertical, Space.x2)
                    } else {
                        Text("Recientes")
                            .typeEyebrow()
                            .padding(.horizontal, Space.x3)
                            .padding(.top, Space.x3)
                            .padding(.bottom, Space.x1)
                        ForEach(
                            Array(chat.recents.enumerated()), id: \.element.id
                        ) { i, meta in
                            DropdownRow(
                                title: meta.title,
                                subtitle: Self.relative(meta.updatedAt),
                                selected: meta.id == chat.conversationId,
                                index: i + 1,
                                titleMaxWidth: .infinity
                            ) {
                                voice.hangUp()
                                chat.openConversation(meta.id)
                                withAnimation(.springSheet) { host.dismiss() }
                            }
                        }
                    }
                }
                .padding(Space.x3)
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
    }

    private var header: some View {
        HStack {
            Text("Conversaciones")
                .font(.uiTitle)
                .foregroundStyle(Semantic.foreground)
            Spacer()
            RoundIconButton(
                icon: .cross,
                foreground: Semantic.foreground,
                background: Semantic.surface,
                help: "Cerrar"
            ) {
                withAnimation(.springSheet) { host.dismiss() }
            }
        }
        .padding(.horizontal, Space.x5)
        .padding(.top, Space.x5)
        .padding(.bottom, Space.x3)
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "es")
        return f.localizedString(for: date, relativeTo: Date())
    }
}
