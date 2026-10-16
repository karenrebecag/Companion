import AppKit
import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

/// A file as a chip: its kind, its name, and two actions. The name truncates
/// past the chip's width; the full path is only in the tooltip.
struct FileChipView: View {
    let chip: FileChip

    /// The icon Finder shows for this kind of file, so a chip matches the
    /// folder it came from. The type is read from the name, not from the disk:
    /// a chip for a file that moved still has its icon.
    static func icon(forFileNamed name: String, isFolder: Bool) -> NSImage {
        let type = isFolder
            ? UTType.folder
            : UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    var body: some View {
        let home = NSHomeDirectory()
        // The file the model read: the working folder first, then home.
        let resolved = FileChip.resolved(chip.path, workdir: WorkdirPreference.stored, home: home)
        let url = URL(fileURLWithPath: resolved)
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let action = FileChip.action(for: resolved, home: home, runnable: FileChip.isRunnable)
        Button {
            switch action {
            case .open: NSWorkspace.shared.open(url)
            case .revealOnly: NSWorkspace.shared.activateFileViewerSelecting([url])
            case .none: break
            }
        } label: {
            HStack(spacing: Space.x2) {
                Image(nsImage: Self.icon(forFileNamed: chip.name, isFolder: isFolder))
                    .resizable()
                    .frame(width: CardMetrics.fileChipIcon, height: CardMetrics.fileChipIcon)
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
                    .stroke(Semantic.border, lineWidth: Stroke.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == .none)
        .help(FileChip.tooltip(url.path, home: home))
        .accessibilityLabel(chip.name)
        .contextMenu {
            if action == .open {
                Button(Localized.string("file.chip.open")) { NSWorkspace.shared.open(url) }
            }
            if action != .none {
                Button(Localized.string("file.chip.reveal")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
}
