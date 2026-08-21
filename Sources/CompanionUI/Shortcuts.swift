import Foundation
import SwiftUI

/// Keyboard shortcut action.
public enum ShortcutAction: String, Codable, CaseIterable {
    case toggleVoice = "toggleVoice"
    case toggleMute = "toggleMute"
    case hangUp = "hangUp"

    public var label: String {
        switch self {
        case .toggleVoice: "Iniciar/terminar turno"
        case .toggleMute: "Silenciar/activar sonido"
        case .hangUp: "Terminar llamada"
        }
    }
}

/// Keyboard modifiers.
public struct KeyModifiers: Codable, Equatable, Hashable {
    public var command: Bool = false
    public var shift: Bool = false
    public var option: Bool = false
    public var control: Bool = false

    public init(command: Bool = false, shift: Bool = false,
                option: Bool = false, control: Bool = false) {
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// Parse from NSEvent modifierFlags.
    public static func from(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        KeyModifiers(
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
    }

    public func toNSEventModifierFlags() -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    /// String representation for display.
    public func display() -> String {
        var parts: [String] = []
        if command { parts.append("Cmd") }
        if shift { parts.append("Shift") }
        if option { parts.append("Opt") }
        if control { parts.append("Ctrl") }
        return parts.joined(separator: "+")
    }
}

/// A single keyboard shortcut binding.
public struct Shortcut: Codable, Equatable {
    public let action: ShortcutAction
    public let keyCode: UInt16
    public let modifiers: KeyModifiers

    public init(action: ShortcutAction, keyCode: UInt16, modifiers: KeyModifiers) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Check if this shortcut conflicts with another (same key binding).
    public func conflictsWith(_ other: Shortcut) -> Bool {
        self.keyCode == other.keyCode && self.modifiers == other.modifiers
    }

    /// Display string for the shortcut.
    public func displayKey() -> String {
        // Map common key codes to display strings
        let keyName = keyCodeToName(keyCode) ?? "Key(\(keyCode))"
        return "\(modifiers.display())\(modifiers.display().isEmpty ? "" : "+")\(keyName)"
    }

    private func keyCodeToName(_ code: UInt16) -> String? {
        // Common key codes
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        default: return nil
        }
    }
}

/// Set of shortcuts, persistable and conflict-free.
public struct ShortcutSet: Codable {
    public var shortcuts: [Shortcut]

    public init(shortcuts: [Shortcut] = []) {
        self.shortcuts = shortcuts
    }

    /// Default shortcuts.
    public static var defaults: ShortcutSet {
        ShortcutSet(shortcuts: [
            Shortcut(action: .toggleVoice,
                    keyCode: 49,
                    modifiers: KeyModifiers(command: true, option: true)),
            Shortcut(action: .toggleMute,
                    keyCode: 46,
                    modifiers: KeyModifiers(command: true, option: true)),
        ])
    }

    /// Check if any shortcuts conflict.
    public func hasConflicts() -> [Shortcut] {
        var conflicts: [Shortcut] = []
        for (i, shortcut) in shortcuts.enumerated() {
            for other in shortcuts[(i + 1)...] {
                if shortcut.conflictsWith(other) {
                    conflicts.append(shortcut)
                    break
                }
            }
        }
        return conflicts
    }

    /// Persist to UserDefaults.
    public func save(key: String = "companionShortcuts") {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    /// Load from UserDefaults.
    public static func load(key: String = "companionShortcuts") -> ShortcutSet {
        guard let data = UserDefaults.standard.data(forKey: key),
              let set = try? JSONDecoder().decode(ShortcutSet.self, from: data)
        else {
            return ShortcutSet.defaults
        }
        return set
    }
}

// MARK: - Shortcut resolution (pure logic)

public enum ShortcutResolver {
    /// Resolve a keyboard event to a shortcut action.
    /// Returns nil if no match is found or if a text field is focused.
    public static func resolve(
        keyCode: UInt16,
        modifiers: KeyModifiers,
        in set: ShortcutSet,
        textFieldFocused: Bool = false
    ) -> ShortcutAction? {
        // Text fields win: do not fire shortcuts when typing.
        guard !textFieldFocused else { return nil }

        for shortcut in set.shortcuts {
            if shortcut.keyCode == keyCode && shortcut.modifiers == modifiers {
                return shortcut.action
            }
        }
        return nil
    }
}

// MARK: - Display constants for key code names

private let keyCodeNames: [UInt16: String] = [
    49: "Space",
    36: "Return",
    51: "Delete",
    53: "Escape",
    123: "Left",
    124: "Right",
    125: "Down",
    126: "Up",
    // Letter keys
    0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
    34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
    12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
    16: "Y", 6: "Z",
]
