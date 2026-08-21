import CompanionCore
import SwiftUI

/// Renders a GalleryBlock as a horizontal scroll of image thumbnails.
struct GalleryCard: View {
    let block: GalleryBlock

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            // Title
            if let title = block.title, !title.isEmpty {
                Text(title)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Semantic.foreground)
            }

            // Horizontal scroll of thumbnails
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.x3) {
                    ForEach(Array(block.images.enumerated()), id: \.offset) { _, item in
                        imageTile(item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.x4)
        .background(Semantic.surface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Semantic.border, lineWidth: 1)
        )
    }

    private func imageTile(_ item: GalleryBlock.Item) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Button {
                open(item)
            } label: {
                imageView(item)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Semantic.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .lineLimit(2)
                    .frame(width: 120, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func imageView(_ item: GalleryBlock.Item) -> some View {
        if let path = item.path {
            // Local file
            Image(nsImage: NSImage(contentsOfFile: path) ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let raw = item.url, let url = URL(string: raw) {
            // HTTPS URL
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder()
                default:
                    placeholder()
                }
            }
        } else {
            placeholder()
        }
    }

    private func placeholder() -> some View {
        ZStack {
            Semantic.muted
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(Semantic.border)
        }
    }

    private func open(_ item: GalleryBlock.Item) {
        if let path = item.path {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else if let raw = item.url, let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }
}
