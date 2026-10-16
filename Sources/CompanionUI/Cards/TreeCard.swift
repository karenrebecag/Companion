import CompanionCore
import SwiftUI

/// A folder listing you can open and close. Folders start closed: the card is
/// a map of where to look, and each folder is opened when asked for.
struct TreeCard: View {
    let block: TreeBlock

    @State private var expanded: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let indent: CGFloat = Space.x4

    var body: some View {
        let rows = Self.rows(block.nodes, parent: "", depth: 0, expanded: expanded)
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(block.title)
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.foreground)
            VStack(alignment: .leading, spacing: Space.x1) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
            if block.truncated {
                Text(String(format: Localized.string("card.tree.truncated"), block.shown, block.total))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// One visible line: a node, its depth, and its path as identity.
    struct Row: Identifiable {
        let id: String
        let node: TreeBlock.Node
        let depth: Int
    }

    /// The lines on screen: an open folder's children follow it, a closed one's
    /// do not exist for the view.
    static func rows(_ nodes: [TreeBlock.Node], parent: String, depth: Int, expanded: Set<String>) -> [Row] {
        nodes.flatMap { node -> [Row] in
            let path = parent + "/" + node.name
            let line = Row(id: path, node: node, depth: depth)
            guard node.isFolder, expanded.contains(path) else { return [line] }
            return [line] + rows(node.children, parent: path, depth: depth + 1, expanded: expanded)
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        let openable = row.node.isFolder && !row.node.children.isEmpty
        let isOpen = expanded.contains(row.id)
        let line = HStack(spacing: Space.x2) {
            Group {
                if openable {
                    Image(systemName: "chevron.right")
                        .font(.uiCaption)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .animation(ChromeMotion.animation(.expoOut(MotionTime.panel), reduceMotion: reduceMotion), value: isOpen)
                } else {
                    Color.clear
                }
            }
            .frame(width: CardMetrics.iconColumn)
            Image(systemName: Self.symbol(for: row.node))
                .font(.uiBody)
                .foregroundStyle(row.node.isFolder ? Semantic.accent : Semantic.mutedForeground)
            Text(row.node.name)
                .font(.uiBody)
                .foregroundStyle(Semantic.foreground)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * Self.indent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if openable {
            Button {
                toggle(row.id)
            } label: {
                line
            }
            .buttonStyle(.plain)
            .accessibilityValue(Localized.string(isOpen ? "card.tree.expanded" : "card.tree.collapsed"))
        } else {
            line
        }
    }

    private func toggle(_ path: String) {
        withAnimation(ChromeMotion.animation(.expoOut(MotionTime.panel), reduceMotion: reduceMotion)) {
            apply(path)
        }
    }

    private func apply(_ path: String) {
        if expanded.contains(path) {
            expanded.remove(path)
        } else {
            expanded.insert(path)
        }
    }

    /// The kind is read from the name: what a person scans a folder for.
    static func symbol(for node: TreeBlock.Node) -> String {
        if node.isFolder { return "folder" }
        switch (node.name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tif", "tiff": return "photo"
        case "mp4", "mov", "m4v", "avi", "mkv": return "film"
        case "mp3", "wav", "m4a", "aac", "flac": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "tgz", "7z", "rar", "dmg": return "archivebox"
        case "csv", "xlsx", "numbers": return "tablecells"
        case "txt", "md", "rtf", "doc", "docx", "pages": return "doc.text"
        case "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "c", "h", "cpp",
             "m", "sh", "json", "yaml", "yml", "toml", "html", "css":
            return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}
