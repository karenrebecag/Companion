import AppKit
import Foundation

/// Monitors global keyboard events and dispatches shortcut actions.
/// Installed once per app lifetime in the main window.
final class KeyboardMonitor: @unchecked Sendable {
    private var monitor: Any?
    private let onAction: @MainActor (ShortcutAction) -> Void
    private let shortcuts: ShortcutSet

    init(
        shortcuts: ShortcutSet,
        onAction: @escaping @MainActor (ShortcutAction) -> Void
    ) {
        self.shortcuts = shortcuts
        self.onAction = onAction
        self.monitor = nil
    }

    /// Start listening to keyboard events.
    /// Only call once per instance; the monitor lives until app exit.
    func start() {
        guard monitor == nil else { return }

        // Install a local event monitor for keyboard events.
        // NSEvent.addLocalMonitorForEvents is safer than global monitor
        // (won't receive events from background apps).
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Check if a text field is focused by examining the responder chain.
            let textFieldFocused = NSApp.keyWindow?.firstResponder is NSTextView

            let modifiers = KeyModifiers.from(event.modifierFlags)
            if let action = ShortcutResolver.resolve(
                keyCode: event.keyCode,
                modifiers: modifiers,
                in: self.shortcuts,
                textFieldFocused: textFieldFocused
            ) {
                // Dispatch action on main thread.
                Task { @MainActor in
                    self.onAction(action)
                }
                // Consume the event: don't pass to other handlers.
                return nil
            }

            // Let through events that don't match any shortcut.
            return event
        }
    }
}
