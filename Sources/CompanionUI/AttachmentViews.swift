import AppKit
import CompanionCore
import SwiftUI

struct DropVeil: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Semantic.scrim)
                .ignoresSafeArea()
            VStack(spacing: Space.x2) {
                Image(systemName: "arrow.down.doc")
                    .font(Fonts.sans(IconSize.hero).weight(.light))
                    .foregroundStyle(Semantic.foreground)
                Text(Localized.string("attach.drop.title"))
                    .font(.uiTitle)
                    .foregroundStyle(Semantic.foreground)
                Text(Localized.string("attach.drop.subtitle"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            .padding(Space.x6)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

/// Not a palette despite the name: how an attachment looks is the file's
/// own picture (or its Finder icon) and its size; it carries no color.
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
