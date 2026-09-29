import AppKit
import CompanionCore
import SwiftUI

/// The comments modal (16m-7): mood, words, optional screenshots, counter.
/// 480 wide, padding 32, radius 28 (Incredible's measures). It lives with
/// the main window because the island's panel cannot hold a 480 form; the
/// island's menu entry opens it there.
struct FeedbackModal: View {
    let model: FeedbackModel
    let onClose: () -> Void
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            Text(Localized.string("feedback.title"))
                .font(GeistFont.uiSubtitle)
                .foregroundStyle(Semantic.foreground)
                .accessibilityAddTraits(.isHeader)
            if model.phase == .sent {
                sent
            } else {
                form
            }
        }
        .padding(FeedbackMetrics.padding)
        .frame(width: FeedbackMetrics.width)
        .background(Semantic.surfaceOverlay)
        .clipShape(RoundedRectangle(cornerRadius: FeedbackMetrics.radius))
        .overlay(RoundedRectangle(cornerRadius: FeedbackMetrics.radius)
            .stroke(Semantic.border, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { typing = true }
        .onChange(of: model.phase) { _, phase in if phase == .closed { onClose() } }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            moods
            field
            captures
            if let note = model.note {
                Text(note).font(GeistFont.uiCaption).foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.x3) {
                AppButton(Localized.string("feedback.cancel"), kind: .secondary) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                AppButton(Localized.string("feedback.send"), kind: .primary, systemImage: "paperplane") { model.send() }
                    .disabled(!model.canSend)
            }
        }
    }

    private var sent: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            Text(Localized.string("feedback.sent"))
                .font(GeistFont.uiLabel)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if let note = model.note {
                Text(note).font(GeistFont.uiCaption).foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                AppButton(Localized.string("feedback.done"), kind: .primary) { model.cancel() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var moods: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(Localized.string("feedback.mood.title"))
                .font(GeistFont.uiCaption).foregroundStyle(Semantic.mutedForeground)
            HStack(spacing: Space.x2) {
                ForEach(FeedbackMood.allCases, id: \.self) { mood in
                    let picked = model.mood == mood
                    Button {
                        model.mood = picked ? nil : mood
                    } label: {
                        VStack(spacing: Space.x1) {
                            Image(systemName: mood.symbol)
                            Text(mood.title).font(GeistFont.uiCaption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.x2_5)
                        .foregroundStyle(picked ? Semantic.primaryForeground : Semantic.foreground)
                        .background(RoundedRectangle(cornerRadius: Radius.chip)
                            .fill(picked ? Semantic.primary : Semantic.muted))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mood.title)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
        }
    }

    private var field: some View {
        VStack(alignment: .trailing, spacing: Space.x1) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(get: { model.text }, set: { model.setText($0) }))
                    .font(GeistFont.uiLabel)
                    .scrollContentBackground(.hidden)
                    .focused($typing)
                    .frame(height: Container.hero)
                    .accessibilityLabel(Localized.string("feedback.placeholder"))
                if model.text.isEmpty {
                    Text(Localized.string("feedback.placeholder"))
                        .font(GeistFont.uiLabel).foregroundStyle(Semantic.faintForeground)
                        .padding(.leading, Space.x1).padding(.top, Space.x2)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .padding(Space.x2)
            .background(RoundedRectangle(cornerRadius: Radius.chip).fill(Semantic.muted))
            let counter = FeedbackCopy.counter(remaining: model.draft.remaining)
            Text(counter.text)
                .font(GeistFont.uiCaption)
                .foregroundStyle(counter.over ? Semantic.danger : Semantic.mutedForeground)
        }
    }

    private var captures: some View {
        HStack(spacing: Space.x2) {
            ForEach(Array(model.captures.enumerated()), id: \.element) { index, url in
                ZStack(alignment: .topTrailing) {
                    Thumbnail(url: url)
                        .accessibilityLabel(String(format: Localized.string("feedback.capture.item"), index + 1))
                    CloseButton(variant: .onMedia,
                                label: String(format: Localized.string("feedback.capture.remove"), index + 1)) {
                        model.removeCapture(url)
                    }
                }
            }
            if model.captures.count < FeedbackDraft.maxCaptures {
                // The only way a capture starts: this button.
                Button {
                    Task { await model.addCapture() }
                } label: {
                    Label(Localized.string("feedback.capture.add"), systemImage: "camera.viewfinder")
                }
                .buttonStyle(CapsuleChipStyle(ink: .choice(selected: false), density: .compact))
                .accessibilityHint(Localized.string("feedback.note.captureAction"))
            }
            Spacer(minLength: Space.none)
        }
    }
}

private struct Thumbnail: View {
    let url: URL

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Semantic.muted
            }
        }
        .frame(width: Space.x14, height: Space.x10)
        .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
    }
}
