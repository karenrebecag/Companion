import Foundation

public enum MenuCommand: String, Sendable, Equatable {
    case about, settings, hide, hideOthers, showAll, quit
    case undo, redo, cut, copy, paste, pastePlain, selectAll
    case attach, newConversation, history
    case toggleVoice, toggleMute, hangUp
    case minimize, close, bringAllToFront
}

public struct MenuItemPlan: Sendable, Equatable {
    public let title: String
    public let command: MenuCommand?
    public let keyEquivalent: String
    public let modifiers: KeyModifiers

    public var isSeparator: Bool { command == nil }

    public init(
        title: String,
        command: MenuCommand?,
        keyEquivalent: String,
        modifiers: KeyModifiers
    ) {
        self.title = title
        self.command = command
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers
    }

    public static func separator() -> MenuItemPlan {
        MenuItemPlan(
            title: "", command: nil, keyEquivalent: "", modifiers: KeyModifiers())
    }
}

public struct MenuSectionPlan: Sendable, Equatable {
    public let title: String
    public let items: [MenuItemPlan]

    public init(title: String, items: [MenuItemPlan]) {
        self.title = title
        self.items = items
    }
}

/// Closures the App layer fills. The plan itself never names a ViewModel.
public struct MenuRouting {
    public var openSettings: () -> Void
    public var attach: () -> Void
    public var newConversation: () -> Void
    public var history: () -> Void
    public var toggleVoice: () -> Void
    public var toggleMute: () -> Void
    public var hangUp: () -> Void

    public init(
        openSettings: @escaping () -> Void,
        attach: @escaping () -> Void,
        newConversation: @escaping () -> Void,
        history: @escaping () -> Void,
        toggleVoice: @escaping () -> Void,
        toggleMute: @escaping () -> Void,
        hangUp: @escaping () -> Void
    ) {
        self.openSettings = openSettings
        self.attach = attach
        self.newConversation = newConversation
        self.history = history
        self.toggleVoice = toggleVoice
        self.toggleMute = toggleMute
        self.hangUp = hangUp
    }
}

public extension Notification.Name {
    static let companionShortcutsDidChange = Notification.Name(
        "companion.shortcutsDidChange")
    /// Wave 16d: the menus follow a language picked in Settings.
    static let companionLanguageDidChange = Notification.Name(
        "companion.languageDidChange")
    static let companionOpenSettings = Notification.Name(
        "companion.openSettings")
    static let companionAttach = Notification.Name(
        "companion.attach")
    static let companionChromeDidChange = Notification.Name(
        "companion.chromeDidChange")
    static let companionProfileDidChange = Notification.Name(
        "companion.profileDidChange")
    /// 15b code review (medio): `dictationKey` changed in Settings — the App
    /// layer rebuilds (or tears down) the dictation `HoldKeyTap`. `nonisolated`:
    /// posted from `VoiceProfile.settings`, itself `nonisolated` so any
    /// thread can persist a voice setting.
    nonisolated static let companionDictationKeyDidChange = Notification.Name(
        "companion.dictationKeyDidChange")
    /// Wave 17: "Detener manos" from the island's chip — CompanionMain owns
    /// the bridge host, so the panel (which does not) asks by notification,
    /// same seam as `companionAttach`.
    static let companionStopHands = Notification.Name(
        "companion.stopHands")
    /// 16k-3: the island's "Conectar X" card opens the window on the Apps
    /// page with that app front and center; `object` is the slug.
    static let companionOpenApps = Notification.Name(
        "companion.openApps")
    /// 16k-3: an account connected or disconnected — the apps runner
    /// re-pulls its tool cache without waiting out the TTL.
    static let companionAppsChanged = Notification.Name(
        "companion.appsChanged")
    /// Wave 17: the "Lend your hands" toggle changed — the App layer starts
    /// or stops the bridge listener without a relaunch.
    nonisolated static let companionHandsLendingDidChange = Notification.Name(
        "companion.handsLendingDidChange")
}

public enum MenuPlan {
    public static func build(shortcuts: ShortcutSet) -> [MenuSectionPlan] {
        [
            MenuSectionPlan(title: "Companion", items: appItems(shortcuts)),
            MenuSectionPlan(title: Localized.string("menu.edit"), items: editItems()),
            MenuSectionPlan(title: Localized.string("menu.conversation"), items: conversationItems(shortcuts)),
            MenuSectionPlan(title: Localized.string("menu.window"), items: windowItems()),
        ]
    }

    private static func appItems(_ shortcuts: ShortcutSet) -> [MenuItemPlan] {
        [
            fixed(Localized.string("menu.item.about"), .about),
            .separator(),
            bound(.settings, Localized.string("menu.item.settings"), shortcuts),
            .separator(),
            item(Localized.string("menu.item.hide"), .hide, "h", KeyModifiers(command: true)),
            item(
                Localized.string("menu.item.hideOthers"), .hideOthers, "h",
                KeyModifiers(command: true, option: true)),
            fixed(Localized.string("menu.item.showAll"), .showAll),
            .separator(),
            item(Localized.string("menu.item.quit"), .quit, "q", KeyModifiers(command: true)),
        ]
    }

    /// Cut/copy/paste/selectAll are macOS muscle memory. ShortcutSet cannot
    /// rebind them: that would make the Edit menu lie.
    private static func editItems() -> [MenuItemPlan] {
        let command = KeyModifiers(command: true)
        return [
            item(Localized.string("menu.item.undo"), .undo, "z", command),
            item(
                Localized.string("menu.item.redo"), .redo, "z",
                KeyModifiers(command: true, shift: true)),
            .separator(),
            item(Localized.string("menu.item.cut"), .cut, "x", command),
            item(Localized.string("menu.item.copy"), .copy, "c", command),
            item(Localized.string("menu.item.paste"), .paste, "v", command),
            item(
                Localized.string("menu.item.pastePlain"), .pastePlain, "v",
                KeyModifiers(command: true, shift: true, option: true)),
            .separator(),
            item(Localized.string("menu.item.selectAll"), .selectAll, "a", command),
        ]
    }

    private static func conversationItems(_ shortcuts: ShortcutSet) -> [MenuItemPlan] {
        [
            bound(.attach, Localized.string("menu.item.attach"), shortcuts),
            .separator(),
            bound(.newConversation, Localized.string("shortcut.newConversation"), shortcuts),
            bound(.history, Localized.string("menu.item.history"), shortcuts),
            .separator(),
            bound(.toggleVoice, Localized.string("menu.item.toggleVoice"), shortcuts),
            bound(.toggleMute, Localized.string("menu.item.toggleMute"), shortcuts),
            bound(.hangUp, Localized.string("menu.item.hangUp"), shortcuts),
        ]
    }

    private static func windowItems() -> [MenuItemPlan] {
        let command = KeyModifiers(command: true)
        return [
            item(Localized.string("menu.item.minimize"), .minimize, "m", command),
            item(Localized.string("menu.item.close"), .close, "w", command),
            .separator(),
            fixed(Localized.string("menu.item.bringAllToFront"), .bringAllToFront),
        ]
    }

    private static func bound(
        _ command: MenuCommand, _ title: String, _ shortcuts: ShortcutSet
    ) -> MenuItemPlan {
        guard let action = command.shortcutAction,
              let shortcut = shortcuts.shortcut(for: action)
        else {
            return item(title, command, "", KeyModifiers())
        }
        return item(title, command, shortcut.keyEquivalent, shortcut.modifiers)
    }

    private static func fixed(_ title: String, _ command: MenuCommand) -> MenuItemPlan {
        item(title, command, "", KeyModifiers())
    }

    private static func item(
        _ title: String, _ command: MenuCommand,
        _ key: String, _ modifiers: KeyModifiers
    ) -> MenuItemPlan {
        MenuItemPlan(
            title: title, command: command,
            keyEquivalent: key, modifiers: modifiers)
    }
}

/// The menu bar item (Wave 16d): Incredible's five, so the app stays
/// reachable with the window closed.
public enum StatusCommand: String, Sendable, Equatable, CaseIterable {
    // Wave 17: `stopHands` sits before `quit` — `StatusBarMenu.rebuild()`
    // draws a separator right before quit, and adding a case here is the
    // only thing that moves an entry ahead of that separator.
    case cancel, show, settings, checkUpdates, stopHands, quit
}

public struct StatusMenuItem: Sendable, Equatable {
    public let command: StatusCommand
    public let title: String
    public let keyEquivalent: String
}

public enum StatusMenuPlan {
    public static var items: [StatusMenuItem] {
        StatusCommand.allCases.map { command in
            StatusMenuItem(
                command: command,
                title: Localized.string(titleKey(for: command)),
                keyEquivalent: command == .cancel ? "\u{1b}" : "")
        }
    }

    /// Every other entry's title lives at "status.<command>"; `stopHands`
    /// uses "menu.stopHands" instead (spec §4), its own catalog entry.
    private static func titleKey(for command: StatusCommand) -> String {
        command == .stopHands ? "menu.stopHands" : "status.\(command.rawValue)"
    }
}

extension MenuCommand {
    var shortcutAction: ShortcutAction? {
        switch self {
        case .settings: .settings
        case .attach: .attach
        case .newConversation: .newConversation
        case .history: .history
        case .toggleVoice: .toggleVoice
        case .toggleMute: .toggleMute
        case .hangUp: .hangUp
        default: nil
        }
    }
}
