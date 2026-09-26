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
            Text("Companion")  // token-exempt: nombre del producto.
                .font(.uiLogo)
                .tracking(Tracking.tighter, at: TypeSize.display)
                .foregroundStyle(Semantic.foreground)
            // No executor choice and no voice/text switch (16j-1): the brain
            // routes on its own and the voice lives in the island.
            HStack(spacing: Space.x2) {
                Spacer()
                HoverIconButton(
                    symbol: "clock.arrow.circlepath",
                    help: Localized.string("header.conversations")
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
        .help(Localized.string("header.settings"))
        .accessibilityLabel(Localized.string("header.settings"))
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
                        title: Localized.string("header.newConversation"),
                        symbol: "square.and.pencil",
                        index: 0,
                        titleMaxWidth: .infinity
                    ) {
                        voice.hangUp()
                        chat.newConversation()
                        withAnimation(.springSheet) { host.dismiss() }
                    }
                    if chat.recents.isEmpty {
                        Text(Localized.string("header.noConversations"))
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.mutedForeground)
                            .padding(.horizontal, Space.x3)
                            .padding(.vertical, Space.x2)
                    } else {
                        Text(Localized.string("header.recent"))
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
            Text(Localized.string("header.conversations"))
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
