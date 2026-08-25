import CompanionCore
import SwiftUI

/// Renders sources extracted from a report as a collapsible panel.
struct SourcesCard: View {
    let webSources: [MarkdownSplitter.SourceLink]
    let fileSources: [String]

    @State private var webExpanded = false
    @State private var filesExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            Text(Localized.string("sources.title"))
                .typeEyebrow()
                .padding(.top, Space.x3)
                .padding(.bottom, Space.x3)

            if !webSources.isEmpty {
                sectionRow(
                    icon: "globe",
                    title: Localized.string("sources.web"),
                    count: webSources.count,
                    isOpen: $webExpanded
                )
                if webExpanded {
                    webList()
                }
            }

            if !webSources.isEmpty && !fileSources.isEmpty {
                Divider()
                    .foregroundStyle(Semantic.border)
            }

            if !fileSources.isEmpty {
                sectionRow(
                    icon: "doc",
                    title: Localized.string("sources.files"),
                    count: fileSources.count,
                    isOpen: $filesExpanded
                )
                if filesExpanded {
                    fileList()
                }
            }
        }
        .cardSurface()
    }

    private func sectionRow(
        icon: String,
        title: String,
        count: Int,
        isOpen: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .springSelect) {
                isOpen.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Space.x3) {
                Image(systemName: icon)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .frame(width: CardMetrics.iconColumn, alignment: .center)

                Text(title)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)

                Spacer()

                Text("\(count)")  // token-exempt: una cifra, no copy.
                    .font(.uiMicro)
                    .foregroundStyle(Semantic.mutedForeground)

                Image(systemName: "chevron.down")
                    .font(.uiMicro)
                    .foregroundStyle(Semantic.mutedForeground)
                    .rotationEffect(.degrees(isOpen.wrappedValue ? 180 : 0))
            }
            .padding(.vertical, Space.x2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func webList() -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            ForEach(Array(webSources.enumerated()), id: \.element.url) { _, link in
                webRow(link)
            }
        }
        .padding(.top, Space.x2)
        .padding(.bottom, Space.x3)
    }

    private func webRow(_ link: MarkdownSplitter.SourceLink) -> some View {
        Button {
            if let url = URL(string: link.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(link.title)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(URL(string: link.url)?.host ?? link.url)
                    .font(Font.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .lineLimit(1)

                if let detail = link.detail, !detail.isEmpty {
                    Text(detail)
                        .font(Font.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.x2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileList() -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            ForEach(Array(fileSources.enumerated()), id: \.element) { _, path in
                fileRow(path)
            }
        }
        .padding(.top, Space.x2)
        .padding(.bottom, Space.x3)
    }

    private func fileRow(_ path: String) -> some View {
        let name = (path as NSString).lastPathComponent
        let ext = (path as NSString).pathExtension.uppercased()

        return Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } label: {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(name)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(ext.isEmpty
                     ? Localized.string("sources.file")
                     : String(format: Localized.string("sources.file.kind"), ext))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.x2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
