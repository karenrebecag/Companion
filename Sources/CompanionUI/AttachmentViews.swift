import AppKit
import CompanionCore
import SwiftUI

struct AttachmentStrip: View {
    var chat: ChatViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.x2) {
                ForEach(chat.pendingAttachments, id: \.id) { ref in
                    chip(ref)
                }
            }
            .padding(.horizontal, Space.x4)
            .padding(.vertical, Space.x1)
        }
        .frame(maxHeight: Space.x8 * 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Archivos adjuntos")
    }

    private func chip(_ ref: AttachmentRef) -> some View {
        HStack(spacing: Space.x1 + Space.x1 / 2) {
            Image(nsImage: AttachmentLook.icon(for: ref))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Space.x8, height: Space.x8)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            VStack(alignment: .leading, spacing: Space.x1 / 4) {
                Text(ref.name)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(1)
                Text(AttachmentLook.detail(ref.byteCount))
                    .font(.uiMicro)
                    .foregroundStyle(Semantic.mutedForeground)
                    .lineLimit(1)
            }
            .frame(maxWidth: Space.x1 * 40, alignment: .leading)
            Button {
                chat.removePending(ref)
            } label: {
                IconGlyph(icon: .cross, size: Space.x2 + Space.x1 / 2)
                    .foregroundStyle(Semantic.mutedForeground)
                    .frame(width: Space.x5, height: Space.x5)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Quitar \(ref.name)")
        }
        .padding(Space.x1 + Space.x1 / 2)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Semantic.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Semantic.border, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ref.name), \(AttachmentLook.detail(ref.byteCount))")
    }
}

struct DropVeil: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Semantic.scrim)
                .ignoresSafeArea()
            VStack(spacing: Space.x2) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: IconSize.hero, weight: .light))
                    .foregroundStyle(Semantic.foreground)
                Text("Suéltalos aquí")
                    .font(.uiTitle)
                    .foregroundStyle(Semantic.foreground)
                Text("Imágenes, PDFs, código: lo que quieras que mire")
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            .padding(Space.x6)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

struct MessageAttachments: View {
    let attachments: [AttachmentRef]
    private let maxVisible = 3
    private var side: CGFloat { Space.x1 * 22 }

    var body: some View {
        let visible = Array(attachments.prefix(maxVisible))
        let overflow = max(0, attachments.count - maxVisible)
        HStack(alignment: .bottom, spacing: Space.x1 + Space.x1 / 2) {
            ForEach(visible, id: \.id) { ref in
                tile(ref)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.mutedForeground)
                    .frame(width: side, height: side)
                    .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Semantic.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .stroke(Semantic.border, lineWidth: Stroke.hairline))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            attachments.count == 1
                ? "1 archivo adjunto" : "\(attachments.count) archivos adjuntos")
    }

    private func tile(_ ref: AttachmentRef) -> some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: ref.path))
        } label: {
            Group {
                if ref.kind == .image {
                    Image(nsImage: AttachmentLook.icon(for: ref))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    VStack(spacing: Space.x1) {
                        Image(nsImage: AttachmentLook.icon(for: ref))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: Space.x8, height: Space.x8)
                        Text(ref.name)
                            .font(.uiMicro)
                            .foregroundStyle(Semantic.mutedForeground)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Space.x1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Semantic.surface)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(Semantic.border, lineWidth: Stroke.hairline))
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(PressableStyle())
        .help(ref.name)
        .accessibilityLabel("\(ref.name). Abrir")
    }
}

enum AttachmentLook {
    static func icon(for ref: AttachmentRef) -> NSImage {
        if ref.kind == .image,
           let image = NSImage(contentsOfFile: ref.path) {
            return image
        }
        return NSWorkspace.shared.icon(forFile: ref.path)
    }

    static func detail(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
