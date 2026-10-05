import Foundation

/// One line of a job's timeline: what the specialist did, in order. Pure so
/// the counting and the wording are testable without instantiating a view.
package struct JobStepInfo: Sendable, Equatable, Codable {
    /// Technical tool name ("WebSearch"), which picks the icon.
    package let tool: String
    /// The step in human words ("WebSearch: vuelos a Lima").
    package let label: String
    /// 16m-2: the runcard shows each step's fate, so `stepFinished` can no
    /// longer be dropped on the floor. Nothing persists steps today, so
    /// the synthesized Codable is enough (review 16m).
    package var done: Bool
    package var failed: Bool
    /// Pairs the step's end with its start; the stream's tool-use id when
    /// there is one, otherwise minted by the reducer.
    package var id: String
    /// The id came from the reducer, not a producer, so no producer id may
    /// ever pair with this step.
    package var minted = false
    /// Both times come from the reducer's injected clock, never from the
    /// executor, so a card's durations are testable and replayable.
    package var startedAt: Date
    package var finishedAt: Date?

    package init(
        tool: String, label: String, done: Bool = false, failed: Bool = false,
        id: String = "", startedAt: Date = .distantPast, finishedAt: Date? = nil
    ) {
        self.tool = tool
        self.label = label
        self.done = done
        self.failed = failed
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

package enum JobSteps: Sendable {
    /// Symbol name per tool. An unknown tool still gets a glyph: a blank slot
    /// reads as a broken row, not as "no icon for this".
    package static func icon(for tool: String) -> String {
        switch tool {
        case Thinking.tool: "lightbulb"
        case "WebSearch": "globe"
        case "WebFetch": "safari"
        case "Read", "NotebookEdit": "doc.text"
        case "Write", "Edit": "pencil.line"
        case "Bash": "terminal"
        case "Grep", "Glob": "magnifyingglass"
        case "Task", "Agent": "person.2"
        case "TodoWrite": "checklist"
        default: "gearshape"
        }
    }

    /// The tool name a thought travels under, so a step is a step everywhere.
    package enum Thinking {
        package static let tool = "Thinking"
    }

    /// "2 searches · 1 file · 1 command" — derived from the steps, never
    /// invented. The same file touched twice is one file. Core has no bundle
    /// to look strings up in, so the language arrives as a parameter.
    package static func summary(
        _ steps: [JobStepInfo], _ language: AppLanguage = .en
    ) -> String? {
        var searches = 0
        var pages = 0
        var commands = 0
        var files: Set<String> = []
        for step in steps {
            switch step.tool {
            // Both vocabularies. These names were Claude Code's only, so a
            // job run by the native executor left a record that said nothing
            // about what it had done — which matters most exactly when you
            // stopped it and want to know how far it got.
            case "WebSearch", "web_search": searches += 1
            case "WebFetch", "web_fetch": pages += 1
            case "Bash", "run_shell": commands += 1
            case "list_directory", "find_places": searches += 1
            case "Read", "Write", "Edit", "NotebookEdit",
                 "read_file", "write_file", "edit_file", "delete_file":
                if let path = path(of: step) {
                    files.insert((path as NSString).lastPathComponent)
                } else {
                    files.insert(step.tool)
                }
            default: break
            }
        }
        let words = SummaryWords(language)
        var parts: [String] = []
        if searches > 0 {
            parts.append(count(searches, words.search, words.searches))
        }
        if pages > 0 { parts.append(count(pages, words.page, words.pages)) }
        if !files.isEmpty {
            parts.append(count(files.count, words.file, words.files))
        }
        if commands > 0 {
            parts.append(count(commands, words.command, words.commands))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Unique paths the job touched, in order.
    package static func files(_ steps: [JobStepInfo]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for step in steps
        where ["Read", "Write", "Edit", "NotebookEdit"].contains(step.tool) {
            guard let path = path(of: step), seen.insert(path).inserted else {
                continue
            }
            out.append(path)
        }
        return out
    }

    /// "Worked 47 s" / "Worked 1:42". Nobody reads "Worked 102 s".
    package static func worked(
        _ seconds: Double, _ language: AppLanguage = .en
    ) -> String {
        let verb = language == .en ? "Worked" : "Trabajó"
        let total = Int(seconds.rounded())
        guard total >= 60 else { return "\(verb) \(total) s" }
        return "\(verb) \(total / 60):\(String(format: "%02d", total % 60))"
    }

    private struct SummaryWords {
        let search, searches, page, pages: String
        let file, files, command, commands: String

        init(_ language: AppLanguage) {
            switch language {
            case .en:
                (search, searches) = ("search", "searches")
                (page, pages) = ("page", "pages")
                (file, files) = ("file", "files")
                (command, commands) = ("command", "commands")
            case .es:
                (search, searches) = ("búsqueda", "búsquedas")
                (page, pages) = ("página", "páginas")
                (file, files) = ("archivo", "archivos")
                (command, commands) = ("comando", "comandos")
            }
        }
    }

    /// The path is whatever follows the verb in the label.
    private static func path(of step: JobStepInfo) -> String? {
        let rest = step.label.split(separator: ":").dropFirst()
            .joined(separator: ":")
            .trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }
}
