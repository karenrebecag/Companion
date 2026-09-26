import AppKit
import CompanionUI

/// The menu bar item (Wave 16d): with the window closed the app is still one
/// click away, as Incredible's is. Five entries from `StatusMenuPlan`.
@MainActor
final class StatusBarMenu: NSObject {
    private let item: NSStatusItem
    private let actions: [StatusCommand: () -> Void]

    init(actions: [StatusCommand: () -> Void]) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.actions = actions
        super.init()
        item.button?.image = NSImage(
            systemSymbolName: "waveform", accessibilityDescription: "Companion")
        rebuild()
    }

    /// The titles follow the language, so the menu is rebuilt each time it
    /// is about to open rather than once at launch.
    func rebuild() {
        let menu = NSMenu()
        for plan in StatusMenuPlan.items {
            if plan.command == .quit { menu.addItem(.separator()) }
            let entry = NSMenuItem(
                title: plan.title, action: #selector(run(_:)), keyEquivalent: plan.keyEquivalent)
            if !plan.keyEquivalent.isEmpty { entry.keyEquivalentModifierMask = [] }
            entry.target = self
            entry.representedObject = plan.command.rawValue
            menu.addItem(entry)
        }
        menu.delegate = self
        item.menu = menu
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let command = StatusCommand(rawValue: raw) else { return }
        actions[command]?()
    }
}

extension StatusBarMenu: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for (entry, plan) in zip(menu.items.filter { !$0.isSeparatorItem }, StatusMenuPlan.items) {
            entry.title = plan.title
        }
    }
}
