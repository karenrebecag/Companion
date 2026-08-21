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
        VStack(spacing: 0) {
            chrome
            hairline
            thread
            if let error = model.errorText {
                Text(error)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.destructive)
                    .padding(.horizontal, Tokens.Space.s16)
                    .padding(.vertical, Tokens.Space.s8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            HStack(spacing: Tokens.Space.s8) {
                Button("Nueva conversación") {
                    voice.hangUp()
                    model.newConversation()
                }
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.fg)
                Button("Cambiar clave") {
                    voice.hangUp()
                    model.changeKey()
                }
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.fg)
                Spacer()
            }
            VoiceControlsView(voice: voice)
            if let status = voice.statusText {
                Text(status)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.muted)
            }
            if !model.recents.isEmpty {
                recentsList
            }
        }
        .padding(.horizontal, Tokens.Space.s16)
        .padding(.vertical, Tokens.Space.s12)
    }

    private var recentsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                ForEach(model.recents) { meta in
                    Button {
                        voice.hangUp()
                        model.openConversation(meta.id)
                    } label: {
                        Text(meta.title)
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.Color.fg)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: Tokens.Space.s24 * 3)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s12) {
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
                .padding(Tokens.Space.s16)
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
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                ForEach(Array(model.queued.enumerated()), id: \.offset) { _, text in
                    Text("En cola: \(text)")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Color.muted)
                        .lineLimit(1)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: Tokens.Space.s8) {
            TextField("Escríbele a Companion", text: $model.draft)
                .textFieldStyle(.plain)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.fg)
                .padding(Tokens.Space.s8)
                .background(Tokens.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Tokens.Color.border, lineWidth: 1)
                )
                .onSubmit(sendText)
                .disabled(voice.isActive)
            Button("Enviar", action: sendText)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.fg)
                .disabled(draftIsEmpty || voice.isActive)
        }
        .padding(Tokens.Space.s16)
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
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if message.role == .user {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: Tokens.Space.s24)
                Text(message.text)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Color.fg)
                    .textSelection(.enabled)
                    .padding(Tokens.Space.s12)
                    .background(Tokens.Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Tokens.Color.border, lineWidth: 1)
                    )
            }
        } else {
            assistantRow(message.text)
        }
    }

    private func assistantRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            MarkdownView(text: text)
            Spacer(minLength: Tokens.Space.s24)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Tokens.Color.border)
            .frame(height: 1)
    }
}
