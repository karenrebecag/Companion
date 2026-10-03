import Foundation

/// Incredible's `classify_command`, as a closed allowlist. `ask` is never a
/// denial: the sheet still decides. A command runs with no sheet only when
/// the whole string is one read. `/bin/sh -c` executes the string, so a
/// metacharacter is the same boundary `ApprovalKey` uses for memory
/// (security review 2026-09-05): `ls; rm` must not inherit a silent `ls`.
package enum CommandClassifier {
    package enum Verdict: Sendable, Equatable {
        case allow
        case ask
    }

    /// Also `ApprovalKey`'s set. Quotes, a backslash and glob characters are
    /// in it because the shell strips them before git sees the token:
    /// `git diff ''--output` would otherwise look like a path and write a file.
    package static let shellMetacharacters = CharacterSet(charactersIn: ";&|`$()<>\n\r{}\\\"'*?[")

    /// Bare names only. A path (`/tmp/ls`) would run whatever sits there.
    private static let readers: Set<String> = [
        "ls", "cat", "head", "wc", "pwd", "whoami", "id",
        "date", "which", "stat", "du", "df", "uname",
        "ps", "grep", "egrep", "fgrep", "mdls", "mdfind",
        "basename", "dirname", "realpath", "readlink", "sw_vers",
    ]

    /// Credentials outside a dotfile. The output of a read goes to the model,
    /// so reading these is handing them over: the sheet decides. Hidden path
    /// components (.ssh, .zshrc, .codex, .git/config) ask on their own.
    private static let secretMarks = [
        "keychains", "credentials", "id_rsa", "id_ed25519", "id_ecdsa", "_history",
        ".pem", ".p12", ".pfx", ".key", "login data", "cookies", "token", "secret",
        "auth", "passw", "chat.db", "library/messages", "library/mail",
    ]

    /// System files with credentials, and devices that never stop writing.
    private static let systemRoots = ["/etc", "/private", "/dev", "/var"]

    private static let greps: Set<String> = ["grep", "egrep", "fgrep"]

    private static let gitReads: Set<String> = [
        "status", "diff", "log", "show", "rev-parse", "ls-files",
        "blame", "describe", "shortlog",
    ]

    /// Flags that do not write and take no separate value. Anything else
    /// that looks like an option (`--output`, `-c`) asks.
    private static let gitFlags: Set<String> = [
        "--", "--short", "--porcelain", "--branch", "-sb", "-s", "-b",
        "--stat", "--name-only", "--name-status", "--oneline",
        "--decorate", "--color=never",
    ]

    package static func classify(_ command: String) -> Verdict {
        guard !command.unicodeScalars.contains(where: { shellMetacharacters.contains($0) }) else {
            return .ask
        }
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first, !first.contains("/") else { return .ask }
        let operands = words.dropFirst()
        if operands.contains(where: touchesSecret) { return .ask }
        // A recursive grep walks into .env and .ssh without naming them.
        if greps.contains(first), operands.contains(where: recurses) { return .ask }
        // Darwin getopt_long accepts any unambiguous prefix (`--rec`, `--foll`),
        // so no long-option spelling can be matched safely.
        if greps.contains(first) || first == "tail", operands.contains(where: { $0.hasPrefix("--") }) {
            return .ask
        }
        if first == "tail" {
            return operands.contains(where: follows) ? .ask : .allow
        }
        // `ps e` / `-E` print every process's environment, API keys included.
        if first == "ps" {
            return operands.contains(where: { $0.contains("E") || (!$0.hasPrefix("-") && $0.contains("e")) })
                ? .ask : .allow
        }
        // An operand that is not a +format asks date to set the clock.
        if first == "date" {
            return operands.allSatisfy({ $0 == "-u" || $0.hasPrefix("+") }) ? .allow : .ask
        }
        // `file -C` / `--compile` writes magic.mgc into the working directory.
        if first == "file" {
            return words.dropFirst().contains(where: { $0.hasPrefix("-") }) ? .ask : .allow
        }
        if readers.contains(first) { return .allow }
        guard first == "git", words.count >= 2, gitReads.contains(words[1]) else { return .ask }
        var paths = false
        for arg in words.dropFirst(2) {
            if arg == "--" { paths = true; continue }
            if paths { continue }
            if gitFlags.contains(arg) { continue }
            if arg.hasPrefix("-") || arg.contains("=") { return .ask }
        }
        return .allow
    }

    /// The command runs git, whose reads depend on the repo's own config.
    package static func isGit(_ command: String) -> Bool {
        command.split(whereSeparator: \.isWhitespace).first == "git"
    }

    private static func touchesSecret(_ word: String) -> Bool {
        let lowered = word.lowercased()
        if secretMarks.contains(where: { lowered.contains($0) }) { return true }
        if systemRoots.contains(where: { lowered == $0 || lowered.hasPrefix($0 + "/") }) { return true }
        return lowered.split(separator: "/").contains(where: { $0.hasPrefix(".") && $0 != "." && $0 != ".." })
    }

    /// `-r`, `-R`, a cluster that holds either, and `-d recurse`. `-d` asks
    /// whatever its value: skip and read are rare enough.
    private static func recurses(_ word: String) -> Bool {
        guard word.hasPrefix("-"), !word.hasPrefix("--") else { return false }
        return word.dropFirst().contains(where: { $0 == "r" || $0 == "R" || $0 == "d" })
    }

    /// `-f`, `-F`, a cluster that holds either (`-fn5`, `-qf`), or any
    /// `--follow` spelling: tail never returns a snapshot then.
    private static func follows(_ word: String) -> Bool {
        if word.hasPrefix("--") { return word.hasPrefix("--follow") }
        guard word.hasPrefix("-") else { return false }
        return word.dropFirst().contains(where: { $0 == "f" || $0 == "F" })
    }
}
