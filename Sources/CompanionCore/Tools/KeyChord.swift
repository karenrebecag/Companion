import Foundation

package enum KeyModifier: String, Sendable, CaseIterable {
    case command, shift, option, control
}

/// The letters a chord may carry. Closed on purpose: each one is in the
/// whitelist because its effect is harmless to undo.
package enum ChordKey: String, Sendable, CaseIterable {
    case n, f, l, t, z
}

package struct KeyChord: Hashable, Sendable {
    package let modifiers: Set<KeyModifier>
    package let key: ChordKey

    package init(modifiers: Set<KeyModifier>, key: ChordKey) {
        self.modifiers = modifiers
        self.key = key
    }

    /// "cmd+shift+n": one fixed order, so a log line and a test read the same
    /// whatever order the model wrote the modifiers in.
    package var name: String {
        let order: [(KeyModifier, String)] = [
            (.command, "cmd"), (.shift, "shift"), (.option, "alt"), (.control, "ctrl"),
        ]
        return (order.filter { modifiers.contains($0.0) }.map(\.1) + [key.rawValue])
            .joined(separator: "+")
    }

    /// New, find, location, new tab, undo, new window with Shift: nothing
    /// here closes, quits, deletes or sends. Select-all is left out on
    /// purpose: select-all then type_text would overwrite a whole document
    /// with no sheet, which a bare type_text never could.
    package static let whitelist: Set<KeyChord> = [
        KeyChord(modifiers: [.command], key: .n), KeyChord(modifiers: [.command], key: .f),
        KeyChord(modifiers: [.command], key: .l), KeyChord(modifiers: [.command], key: .t),
        KeyChord(modifiers: [.command], key: .z),
        KeyChord(modifiers: [.command, .shift], key: .n),
    ]

    package enum Parse: Equatable, Sendable {
        case plain
        case chord(KeyChord)
        case refused(ContractError)
    }

    /// No `+` means a named key and `NamedKey.parse` owns it. Anything with a
    /// `+` is a chord: allowed only when it is exactly on the whitelist.
    package static func parse(_ raw: String) -> Parse {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.contains("+") else { return .plain }
        // A chord is plain ASCII: a lookalike or a zero-width character that
        // trimming would swallow is not a spelling anyone typed on purpose.
        guard text.allSatisfy(\.isASCII) else { return .refused(notAllowed(raw)) }
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, let last = parts.last, !parts.contains(where: \.isEmpty) else {
            return .refused(notAllowed(raw))
        }
        var modifiers: Set<KeyModifier> = []
        for part in parts.dropLast() {
            guard let modifier = modifier(named: part), modifiers.insert(modifier).inserted else {
                return .refused(notAllowed(raw))
            }
        }
        guard let key = ChordKey(rawValue: last) else { return .refused(notAllowed(raw)) }
        let chord = KeyChord(modifiers: modifiers, key: key)
        return whitelist.contains(chord) ? .chord(chord) : .refused(notAllowed(raw))
    }

    private static func modifier(named name: String) -> KeyModifier? {
        switch name {
        case "cmd", "command": .command
        case "shift": .shift
        case "alt", "option", "opt": .option
        case "ctrl", "control": .control
        default: nil
        }
    }

    private static func notAllowed(_ raw: String) -> ContractError {
        let text = raw.lowercased().filter { !$0.isWhitespace }
        let semantic = ["cmd+w", "command+w", "cmd+q", "command+q", "cmd+h", "command+h",
                        "cmd+m", "command+m"].contains(text)
        let allowed = whitelist.map(\.name).sorted().joined(separator: ", ")
        let hint = semantic
            ? "closing, quitting, hiding and minimising cannot be verified: use menu "
                + "(e.g. File > Close, Archivo > Cerrar) instead"
            : "use menu for anything else"
        return ContractError(
            code: "chord_not_allowed",
            message: "\"\(raw)\" is not an allowed shortcut; allowed: \(allowed). \(hint)")
    }
}
