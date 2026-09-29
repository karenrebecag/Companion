import AppKit
import CompanionCore
import CompanionServices
import UniformTypeIdentifiers

/// "Download PNG" from a diagram in the island (16m-5b). Same constraint as
/// the file picker: the island is a non-activating panel, so a save panel
/// from an inactive app opens behind the app in front and cannot take the
/// keyboard. Activate just for the panel, then hand the keyboard back.
/// A save panel is the system's own, so no Downloads-folder permission is
/// needed and she chooses where it goes.
@MainActor
enum IslandSavePanel {
    private static var isOpen = false

    /// Cancelling is her choice; a write that fails is reported as such.
    static func save(_ data: Data, suggestedName: String) async -> DiagramSaveResult {
        guard !isOpen else { return .cancelled }
        isOpen = true
        defer { isOpen = false }
        let previous = NSWorkspace.shared.frontmostApplication
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        NSApp.activate()
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        IslandFilePanel.handBack(to: previous)
        guard response == .OK, let url = panel.url else { return .cancelled }
        return DiagramFileWriter.write(data, to: url)
    }
}
