import AppKit
import CompanionCore
import SwiftUI

/// A file as a chip: its kind, its name, and two actions. The name truncates
/// past the chip's width; the full path is only in the tooltip.
struct FileChipView: View {
    let chip: FileChip

    var body: some View {
        let home = NSHomeDirectory()
        let url = URL(fileURLWithPath: FileChip.expanded(chip.path, home: home))
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: Space.x2) {
                Image(systemName: FileSymbol.name(forFileNamed: chip.name, isFolder: isFolder))
                    .font(.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
                    .accessibilityHidden(true)
                Text(verbatim: chip.name)
                    .font(.uiBody)
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, Space.x3)
            .padding(.vertical, Space.x2)
            .frame(maxWidth: CardMetrics.fileChipWidth, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Semantic.hover))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Semantic.border, lineWidth: Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(FileChip.tooltip(chip.path, home: home))
        .accessibilityLabel(chip.name)
        .contextMenu {
            Button(Localized.string("file.chip.open")) { NSWorkspace.shared.open(url) }
            Button(Localized.string("file.chip.reveal")) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
