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
    static let companionOpenSettings = Notification.Name(
        "companion.openSettings")
}

public enum MenuPlan {
    public static func build(shortcuts: ShortcutSet) -> [MenuSectionPlan] {
        [
            MenuSectionPlan(title: "Companion", items: appItems(shortcuts)),
            MenuSectionPlan(title: "Edición", items: editItems()),
            MenuSectionPlan(title: "Conversación", items: conversationItems(shortcuts)),
            MenuSectionPlan(title: "Ventana", items: windowItems()),
        ]
    }

    private static func appItems(_ shortcuts: ShortcutSet) -> [MenuItemPlan] {
        [
            fixed("Acerca de Companion", .about),
            .separator(),
            bound(.settings, "Ajustes…", shortcuts),
            .separator(),
            item("Ocultar Companion", .hide, "h", KeyModifiers(command: true)),
            item(
                "Ocultar otras", .hideOthers, "h",
                KeyModifiers(command: true, option: true)),
            fixed("Mostrar todo", .showAll),
            .separator(),
            item("Salir de Companion", .quit, "q", KeyModifiers(command: true)),
        ]
    }

    /// Cut/copy/paste/selectAll are macOS muscle memory. ShortcutSet cannot
    /// rebind them: that would make the Edit menu lie.
    private static func editItems() -> [MenuItemPlan] {
        let command = KeyModifiers(command: true)
        return [
            item("Deshacer", .undo, "z", command),
            item(
                "Rehacer", .redo, "z",
                KeyModifiers(command: true, shift: true)),
            .separator(),
            item("Cortar", .cut, "x", command),
            item("Copiar", .copy, "c", command),
            item("Pegar", .paste, "v", command),
            item(
                "Pegar sin formato", .pastePlain, "v",
                KeyModifiers(command: true, shift: true, option: true)),
            .separator(),
            item("Seleccionar todo", .selectAll, "a", command),
        ]
    }

    private static func conversationItems(_ shortcuts: ShortcutSet) -> [MenuItemPlan] {
        [
            bound(.attach, "Adjuntar archivos…", shortcuts),
            .separator(),
            bound(.newConversation, "Nueva conversación", shortcuts),
            bound(.history, "Conversaciones", shortcuts),
            .separator(),
            bound(.toggleVoice, "Iniciar/terminar turno", shortcuts),
            bound(.toggleMute, "Silenciar/activar sonido", shortcuts),
            bound(.hangUp, "Terminar llamada", shortcuts),
        ]
    }

    private static func windowItems() -> [MenuItemPlan] {
        let command = KeyModifiers(command: true)
        return [
            item("Minimizar", .minimize, "m", command),
            item("Cerrar", .close, "w", command),
            .separator(),
            fixed("Traer todo al frente", .bringAllToFront),
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
