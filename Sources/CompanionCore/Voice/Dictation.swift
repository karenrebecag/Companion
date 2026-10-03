import Foundation

/// What a hold of the key does with the words (Wave 12e): talk to
/// Companion, dictate into the text field under the cursor of the app in
/// front, or decide by whether such a field exists.
package enum VoiceMode: String, Sendable, Equatable, CaseIterable {
    case agent, dictation, automatic
}

/// The editable element the app in front has focus on, as the probe saw it
/// at press. `secure` is a password field: never a target.
package struct FocusedField: Sendable, Equatable {
    package let app: String
    package let pid: Int32
    package let secure: Bool

    package init(app: String, pid: Int32, secure: Bool = false) {
        self.app = app
        self.pid = pid
        self.secure = secure
    }
}

/// Why a hold that wanted to dictate talked to Companion instead. A field
/// that vanishes mid-hold is not here: that is an injection failure, decided
/// at release, not at press.
package enum DictationNotice: Sendable, Equatable {
    case noField, needsAccessibility
}

package enum DictationDestination: Sendable, Equatable {
    case agent(DictationNotice?)
    case dictation(FocusedField)
}

/// A failure the chrome reports; `fieldGone` is not one (the words go to
/// Companion and nothing is lost).
package enum DictationFailure: Sendable, Equatable {
    case needsAccessibility
}

/// Decided at press, not at release: the user aimed at the field they were
/// in when they pressed.
package enum DictationRouter {
    package static func destination(
        mode: VoiceMode, field: FocusedField?, trusted: Bool
    ) -> DictationDestination {
        switch mode {
        case .agent:
            return .agent(nil)
        case .dictation:
            guard trusted else { return .agent(.needsAccessibility) }
            guard let field, !field.secure else { return .agent(.noField) }
            return .dictation(field)
        case .automatic:
            guard trusted, let field, !field.secure else { return .agent(nil) }
            return .dictation(field)
        }
    }
}

/// Reads the app in front: is there an editable field under the cursor,
/// and may this process touch it.
package protocol FocusedFieldProbing: Sendable {
    func isTrusted() -> Bool
    func focusedField() -> FocusedField?
}

package enum InjectionRoute: String, Sendable, Equatable {
    case ax, paste
}

package enum InjectionFailure: Sendable, Equatable {
    case needsAccessibility
    /// The app in front is no longer the one probed at press.
    case fieldGone
    /// The element refused (secure, or no longer editable).
    case refused
}

package enum InjectionResult: Sendable, Equatable {
    case injected(Int, via: InjectionRoute)
    case failed(InjectionFailure)
}

/// Puts text into the field probed at press. Implementations must check the
/// target again: the words never land in a different app.
package protocol TextInjecting: Sendable {
    func inject(_ text: String, into field: FocusedField) async -> InjectionResult
}

// MARK: - The parent's hands on the screen (Wave 15g)

/// The keys the parent may press, and no other: each one is safe to post to
/// a process in the background, and none of them is a shortcut. A closed
/// list is the schema — an unknown key is refused, never approximated.
package enum NamedKey: String, Sendable, Equatable, CaseIterable {
    case `return`, tab, escape, up, down, left, right, backspace

    package static func parse(_ raw: String) throws(ContractError) -> NamedKey {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let key = NamedKey(rawValue: name) else {
            throw .invalidArgs(
                "unknown key \"\(raw)\"; use one of: "
                    + allCases.map(\.rawValue).joined(separator: ", "))
        }
        return key
    }
}

/// Posts one key, down and up, with no modifiers, to one process; or one
/// whitelisted chord with exactly its modifiers.
package protocol KeyPressing: Sendable {
    func press(_ key: NamedKey, pid: Int32) -> Bool
    func press(chord: KeyChord, pid: Int32) -> Bool
}

/// Raises the window of `pid` whose title contains `title`; the title it
/// raised, or nil when none matched.
package protocol WindowRaising: Sendable {
    func raise(titleContaining title: String, pid: Int32) -> String?
}

/// The focused element of one process, keyed to that pid rather than to
/// whatever is in front: the parent acts on the app the user was in, and
/// Companion's own window may be the one in front while it does.
package protocol FocusedReading: Sendable {
    func focusedField(pid: Int32) -> FocusedField?
    /// The field's text, clipped; nil for a secure field or no field.
    func read(pid: Int32) -> String?
}

/// Apps that turn typed text into commands or agent instructions: a shell
/// runs what Return sends, and a coding-agent chat (Claude Code, Codex,
/// Cursor's assistant panel) acts on it the same way a shell would. Typing
/// there is not writing, it is issuing an order, so Return and multi-line
/// text need the sheet (H2, security review 2026-09-25 — the original list
/// covered only six shells and missed every editor/agent surface).
package enum CommandApps {
    package static let bundleIDs: Set<String> = [
        // Shells.
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "dev.warp.Warp-Preview", "net.kovidgoyal.kitty",
        "io.alacritty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
        "org.tabby", "dev.zed.Zed",
        // Editors with an integrated terminal/agent panel.
        "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        // Standalone coding-agent apps.
        "com.anthropic.claudefordesktop", "com.openai.codex", "com.openai.chat",
    ]

    package static func isCommandApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }
}

/// "la ventana de Jev" names a window the way it is spoken: no case, no
/// accents. The first match wins, in the app's own window order.
package enum WindowTitles {
    package static func match(_ titles: [String], containing query: String) -> Int? {
        let needle = fold(query)
        guard !needle.isEmpty else { return nil }
        return titles.firstIndex { fold($0).contains(needle) }
    }

    /// Menu items overlap ("Exportar", "Exportar como PDF…"): an exact
    /// folded label wins, and only without one does "contains" decide.
    package static func bestMatch(_ labels: [String], for query: String) -> Int? {
        let needle = fold(query)
        guard !needle.isEmpty else { return nil }
        let folded = labels.map { fold($0).trimmingCharacters(in: CharacterSet(charactersIn: "…. ")) }
        return folded.firstIndex(of: needle) ?? match(labels, containing: query)
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// What `read_focused` hands the model: enough to check what was typed,
/// never a whole document.
package enum FocusedText {
    package static let limit = 500
    /// Of the window around the caret, how much comes before it: what was
    /// just typed matters more than what follows.
    static let beforeCaret = 400

    /// The part of a long field worth reading (review 2026-09-25): around
    /// the caret — a UTF-16 offset, as Accessibility reports it — or, with
    /// none, the end, where a terminal's prompt line and the latest text
    /// are. "…" marks each cut side. Clipping a clipped text changes nothing.
    package static func clip(_ text: String, caret: Int? = nil) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit + 2 else { return trimmed }
        let chars = Array(trimmed)
        let end: Int
        if let caret, let index = characterOffset(caret, in: trimmed), index < chars.count {
            let start = max(0, index - beforeCaret)
            end = min(chars.count, start + limit)
        } else {
            end = chars.count
        }
        let start = max(0, end - limit)
        return (start > 0 ? "…" : "") + String(chars[start..<end]) + (end < chars.count ? "…" : "")
    }

    private static func characterOffset(_ utf16: Int, in text: String) -> Int? {
        guard utf16 >= 0, utf16 <= text.utf16.count else { return nil }
        let index = String.Index(utf16Offset: utf16, in: text)
        return text.distance(from: text.startIndex, to: index)
    }
}
