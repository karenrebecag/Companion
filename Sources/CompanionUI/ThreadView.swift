import CompanionCore
import SwiftUI

public struct ThreadView: View {
    @Bindable var model: ChatViewModel
    @Bindable var voice: VoiceViewModel

    public init(chat: ChatViewModel, voice: VoiceViewModel) {
        self.model = chat
        self.voice = voice
    }

    public var body: some View {
        VStack(spacing: Space.none) {
            chrome
            hairline
            thread
            if let error = model.errorText {
                Text(error)
                    .font(Font.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .padding(.horizontal, Space.x4)
                    .padding(.vertical, Space.x2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(spacing: Space.x2) {
                Button("Nueva conversación") {
                    voice.hangUp()
                    model.newConversation()
                }
                    .font(Font.uiCaption)
                    .foregroundStyle(Semantic.foreground)
                Button("Cambiar clave") {
                    voice.hangUp()
                    model.changeKey()
                }
                    .font(Font.uiCaption)
                    .foregroundStyle(Semantic.foreground)
                Spacer()
            }
            VoiceControlsView(voice: voice)
            if let status = voice.statusText {
                Text(status)
                    .font(Font.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            if !model.recents.isEmpty {
                recentsList
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
    }

    private var recentsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x1) {
                ForEach(model.recents) { meta in
                    Button {
                        voice.hangUp()
                        model.openConversation(meta.id)
                    } label: {
                        Text(meta.title)
                            .font(Font.uiCaption)
                            .foregroundStyle(Semantic.foreground)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: Space.x6 * 3)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.x3) {
                    ForEach(model.messages) { message in
                        messageRow(message)
                    }
                    if !model.streaming.isEmpty {
                        assistantRow(model.streaming)
                    }
                    if model.busy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    queuedRows
                    Color.clear.frame(height: 1).id("thread-end")
                }
                .padding(Space.x4)
            }
            .onChange(of: model.messages.count) { _, _ in
                proxy.scrollTo("thread-end", anchor: .bottom)
            }
            .onChange(of: model.streaming) { _, _ in
                proxy.scrollTo("thread-end", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var queuedRows: some View {
        if !model.queued.isEmpty {
            VStack(alignment: .leading, spacing: Space.x1) {
                ForEach(Array(model.queued.enumerated()), id: \.offset) { _, text in
                    Text("En cola: \(text)")
                        .font(Font.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .lineLimit(1)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: Space.x2) {
            TextField("Escríbele a Companion", text: $model.draft)
                .textFieldStyle(.plain)
                .font(Font.uiBody)
                .foregroundStyle(Semantic.foreground)
                .padding(Space.x2)
                .background(Semantic.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Semantic.border, lineWidth: Stroke.hairline)
                )
                .onSubmit(sendText)
                .disabled(voice.isActive)
            Button("Enviar", action: sendText)
                .font(Font.uiBody)
                .foregroundStyle(Semantic.foreground)
                .disabled(draftIsEmpty || voice.isActive)
        }
        .padding(Space.x4)
    }

    private func sendText() {
        voice.hangUp()
        model.send()
    }

    private var draftIsEmpty: Bool {
        model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.isStatus {
            Text(message.text)
                .font(Font.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if message.role == .user {
            HStack(alignment: .top, spacing: Space.none) {
                Spacer(minLength: Space.x6)
                Text(message.text)
                    .font(Font.uiBody)
                    .foregroundStyle(Semantic.foreground)
                    .textSelection(.enabled)
                    .padding(Space.x3)
                    .background(Semantic.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Semantic.border, lineWidth: Stroke.hairline)
                    )
            }
        } else {
            assistantRow(message.text)
        }
    }

    private func assistantRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.none) {
            MarkdownView(text: text)
            Spacer(minLength: Space.x6)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Semantic.border)
            .frame(height: 1)
    }
}
