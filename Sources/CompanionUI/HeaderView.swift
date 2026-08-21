import CompanionCore
import SwiftUI

public enum InteractionMode: String, Sendable, CaseIterable, Equatable {
    case voice, text
}

public enum HeaderMetrics {
    public static let topClearance: CGFloat = Space.x1 * 10
    public static let avatar: CGFloat = IconSize.hero
}

public struct HeaderView: View {
    var chat: ChatViewModel
    var voice: VoiceViewModel
    var executors: ExecutorChoice?
    @Binding var mode: InteractionMode
    var onSettings: () -> Void

    @Environment(DropdownHost.self) private var host
    @Namespace private var modeNS

    public init(
        chat: ChatViewModel,
        voice: VoiceViewModel,
        executors: ExecutorChoice?,
        mode: Binding<InteractionMode>,
        onSettings: @escaping () -> Void
    ) {
        self.chat = chat
        self.voice = voice
        self.executors = executors
        self._mode = mode
        self.onSettings = onSettings
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
                    onSettings()
                }
                HoverIconButton(symbol: "gearshape", help: "Ajustes") {
                    onSettings()
                }
                avatar
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.top, HeaderMetrics.topClearance)
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
            Image(systemName: "person.crop.circle")
                .font(.uiTitle)
                .foregroundStyle(Semantic.mutedForeground)
                .frame(width: HeaderMetrics.avatar, height: HeaderMetrics.avatar)
                .clipShape(Circle())
                .overlay(Circle().stroke(Semantic.border, lineWidth: Stroke.hairline))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help("Tu perfil")
        .accessibilityLabel("Tu perfil")
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

struct HistoryDropdown: View {
    var chat: ChatViewModel
    var voice: VoiceViewModel
    var host: DropdownHost

    var body: some View {
        DropdownPanel {
            DropdownRow(
                title: "Nueva conversación",
                symbol: "square.and.pencil",
                index: 0
            ) {
                voice.hangUp()
                chat.newConversation()
                withAnimation(.springSheet) { host.dismiss() }
            }
            if !chat.recents.isEmpty {
                Text("Recientes")
                    .typeEyebrow()
                    .padding(.horizontal, Space.x2 + Space.x1 / 2)
                    .padding(.top, Space.x2)
                    .padding(.bottom, Space.x1)
                ForEach(Array(chat.recents.enumerated()), id: \.element.id) { i, meta in
                    DropdownRow(
                        title: meta.title,
                        subtitle: Self.relative(meta.updatedAt),
                        index: i + 1
                    ) {
                        voice.hangUp()
                        chat.openConversation(meta.id)
                        withAnimation(.springSheet) { host.dismiss() }
                    }
                }
            }
        }
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "es")
        return f.localizedString(for: date, relativeTo: Date())
    }
}
