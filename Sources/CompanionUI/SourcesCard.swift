import CompanionCore
import SwiftUI

/// Renders sources extracted from a report as a collapsible panel.
struct SourcesCard: View {
    let webSources: [MarkdownSplitter.SourceLink]
    let fileSources: [String]

    @State private var webExpanded = false
    @State private var filesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fuentes")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Semantic.foreground)
                .textCase(.uppercase)
                .padding(.top, Space.x3)
                .padding(.bottom, Space.x3)

            if !webSources.isEmpty {
                sectionRow(
                    icon: "globe",
                    title: "Web",
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
                    title: "Archivos",
                    count: fileSources.count,
                    isOpen: $filesExpanded
                )
                if filesExpanded {
                    fileList()
                }
            }
        }
        .padding(Space.x4)
        .background(Semantic.surface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Semantic.border, lineWidth: 1)
        )
    }

    private func sectionRow(
        icon: String,
        title: String,
        count: Int,
        isOpen: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOpen.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Space.x3) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Semantic.mutedForeground)
                    .frame(width: 16, alignment: .center)

                Text(title)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Semantic.foreground)

                Spacer()

                Text("\(count)")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Semantic.mutedForeground)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
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
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(URL(string: link.url)?.host ?? link.url)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .lineLimit(1)

                if let detail = link.detail, !detail.isEmpty {
                    Text(detail)
                        .font(Tokens.Typography.caption)
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
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(ext.isEmpty ? "Archivo" : "Archivo \(ext)")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.x2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
