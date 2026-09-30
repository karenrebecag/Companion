import AppKit
import CompanionCore
import UniformTypeIdentifiers

/// The clip's "Choose file…" from the island (spec 16m D1). The island is a
/// non-activating panel and the app in front is usually another one; an open
/// panel from an inactive app opens behind that app and cannot take the
/// keyboard (why 16i-2 sent it to the window). Activating is the composition
/// root's call, so the picker lives here: activate just for the panel, then
/// hand the keyboard back to whoever had it.
///
/// Activating also raises the main window if it is on screen (never one
/// that is closed): the panel opens above it, and when the keyboard goes
/// back the other app's windows cover it again. Keeping it down would mean
/// ordering it out and back, which moves the user's window for a file pick.
@MainActor
enum IslandFilePanel {
    /// One panel at a time, whoever asks (review 16m-3).
    private static var isOpen = false

    static func pick() async -> [URL] {
        guard !isOpen else { return [] }
        isOpen = true
        defer { isOpen = false }
        let previous = NSWorkspace.shared.frontmostApplication
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.item]
        // Left shareable: it is the system's picker, and `.none` would blank
        // it from the user's own screen shares and screenshots as well.
        NSApp.activate()
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        let urls = response == .OK ? panel.urls : []
        handBack(to: previous)
        return urls
    }

    static func handBack(to previous: NSRunningApplication?) {
        guard let previous else { return }
        let current = NSRunningApplication.current
        guard IslandPickerFocus.handsBack(
            previousIsCompanion: previous == current, previousRunning: !previous.isTerminated,
            frontIsCompanion: NSWorkspace.shared.frontmostApplication == current) else { return }
        previous.activate()
    }
}
