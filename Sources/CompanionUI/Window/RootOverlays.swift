import CompanionCore
import SwiftUI

// The recent conversations, the root window's one menu over everything. It
// outlived the header it was born in (retired in 16p-2), so it lives alone.

public enum HistoryOverlayMetrics {
    public static let maxSide: CGFloat = SettingsOverlayMetrics.maxSide
    public static let minWidth: CGFloat = 300
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
            CloseButton {
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
