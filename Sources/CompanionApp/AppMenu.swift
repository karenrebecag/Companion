import AppKit
import CompanionUI

/// The app shipped without NSApp.mainMenu, and in Cocoa that is not
/// cosmetic: edit shortcuts live on menu items, not on the text field.
final class AppMenu: NSObject {
    /// NSMenu does not retain its target. Without this anchor ARC collects
    /// the controller and custom actions stop responding.
    private static var installed: AppMenu?

    private let routing: MenuRouting
    private var observer: NSObjectProtocol?

    private init(routing: MenuRouting) {
        self.routing = routing
        super.init()
        observer = NotificationCenter.default.addObserver(
            forName: .companionShortcutsDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in AppMenu.rebuild() }
        }
    }

    static func install(routing: MenuRouting) {
        let menu = AppMenu(routing: routing)
        installed = menu
        NSApp.mainMenu = menu.build(shortcuts: ShortcutSet.load())
    }

    static func rebuild() {
        guard let installed else { return }
        NSApp.mainMenu = installed.build(shortcuts: ShortcutSet.load())
    }

    private func build(shortcuts: ShortcutSet) -> NSMenu {
        let bar = NSMenu()
        let plan = MenuPlan.build(shortcuts: shortcuts)
        for section in plan {
            let submenu = NSMenu(title: section.title)
            for item in section.items {
                submenu.addItem(nsItem(item))
            }
            bar.addItem(branch(section.title, submenu))
            if section.title == "Ventana" {
                NSApp.windowsMenu = submenu
            }
        }
        return bar
    }

    private func nsItem(_ plan: MenuItemPlan) -> NSMenuItem {
        if plan.isSeparator { return .separator() }
        let item = NSMenuItem(
            title: plan.title,
            action: selector(plan.command),
            keyEquivalent: plan.keyEquivalent)
        if !plan.keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = plan.modifiers.toNSEventModifierFlags()
        }
        // Edit and system items travel the responder chain. Custom ones hit us.
        item.target = usesResponderChain(plan.command) ? nil : self
        return item
    }

    private func branch(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = title
        item.submenu = submenu
        return item
    }

    private func usesResponderChain(_ command: MenuCommand?) -> Bool {
        switch command {
        case .undo, .redo, .cut, .copy, .paste, .pastePlain, .selectAll,
             .about, .hide, .hideOthers, .showAll, .quit,
             .minimize, .close, .bringAllToFront:
            true
        default:
            false
        }
    }

    private func selector(_ command: MenuCommand?) -> Selector? {
        switch command {
        case .about: #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        case .hide: #selector(NSApplication.hide(_:))
        case .hideOthers: #selector(NSApplication.hideOtherApplications(_:))
        case .showAll: #selector(NSApplication.unhideAllApplications(_:))
        case .quit: #selector(NSApplication.terminate(_:))
        case .undo: Selector(("undo:"))
        case .redo: Selector(("redo:"))
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .pastePlain: #selector(NSTextView.pasteAsPlainText(_:))
        case .selectAll: #selector(NSText.selectAll(_:))
        case .minimize: #selector(NSWindow.performMiniaturize(_:))
        case .close: #selector(NSWindow.performClose(_:))
        case .bringAllToFront: #selector(NSApplication.arrangeInFront(_:))
        case .settings: #selector(openSettings)
        case .attach: #selector(attachFiles)
        case .newConversation: #selector(newConversation)
        case .history: #selector(openHistory)
        case .toggleVoice: #selector(toggleVoice)
        case .toggleMute: #selector(toggleMute)
        case .hangUp: #selector(hangUp)
        case nil: nil
        }
    }

    @objc private func openSettings() { routing.openSettings() }
    @objc private func attachFiles() { routing.attach() }
    @objc private func newConversation() { routing.newConversation() }
    @objc private func openHistory() { routing.history() }
    @objc private func toggleVoice() { routing.toggleVoice() }
    @objc private func toggleMute() { routing.toggleMute() }
    @objc private func hangUp() { routing.hangUp() }
}
