import CompanionCore
import CompanionUIPro
import SwiftUI

/// A folder structure the model expanded, as a tree that opens and closes.
struct PresentTree: View {
    let files: PresentFiles

    var body: some View {
        TreeView(
            nodes: Self.nodes(files.items, parent: ""),
            label: PresentStrings.label(files.title, fallback: "present.files"))
    }

    /// Ids are paths so two files with one name in different folders stay apart.
    static func nodes(_ items: [PresentFile], parent: String) -> [TreeNode] {
        items.map { item in
            let id = parent.isEmpty ? item.name : parent + "/" + item.name
            return TreeNode(
                id: id, label: item.name,
                symbol: FileSymbol.name(forFileNamed: item.name, isFolder: item.children != nil),
                children: item.children.map { nodes($0, parent: id) })
        }
    }
}

/// Files the model named without a place on disk. They are labels, not
/// buttons: there is no path to open from a bare name.
struct PresentChips: View {
    let files: PresentFiles

    var body: some View {
        WrappingRow(spacing: Space.x2) {
            ForEach(Array(files.items.enumerated()), id: \.offset) { _, file in
                HStack(spacing: Space.x2) {
                    Image(systemName: FileSymbol.name(forFileNamed: file.name, isFolder: false))
                        .font(.uiBody)
                        .foregroundStyle(Semantic.mutedForeground)
                        .accessibilityHidden(true)
                    Text(verbatim: file.name)
                        .font(.uiBody)
                        .foregroundStyle(Semantic.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let size = file.size, !size.isEmpty {
                        Text(size)
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.mutedForeground)
                    }
                }
                .padding(.horizontal, Space.x3)
                .padding(.vertical, Space.x2)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(Semantic.hover))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Semantic.border, lineWidth: Stroke.hairline))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Code, or a diff when the model gave the text before and after.
struct PresentCodeView: View {
    let code: PresentCode
    let measures: PresentMeasures

    var body: some View {
        if let before = code.before, let after = code.after {
            CodeBlock(
                code: after, filename: name, language: language,
                maxLines: measures.codeMaxLines, original: before, initiallyReviewing: true)
        } else {
            CodeBlock(
                code: code.code ?? "", filename: name, language: language,
                maxLines: measures.codeMaxLines)
        }
    }

    private var name: String { PresentStrings.label(code.title, fallback: "present.code.file") }
    private var language: String { code.language ?? "text" }
}
