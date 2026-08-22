import Foundation

/// One line of a job's timeline: what the specialist did, in order. Pure so
/// the counting and the wording are testable without instantiating a view.
public struct JobStepInfo: Sendable, Equatable, Codable {
    /// Technical tool name ("WebSearch"), which picks the icon.
    public let tool: String
    /// The step in human words ("WebSearch: vuelos a Lima").
    public let label: String

    public init(tool: String, label: String) {
        self.tool = tool
        self.label = label
    }
}

public enum JobSteps: Sendable {
    /// Symbol name per tool. An unknown tool still gets a glyph: a blank slot
    /// reads as a broken row, not as "no icon for this".
    public static func icon(for tool: String) -> String {
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
    public enum Thinking {
        public static let tool = "Thinking"
    }

    /// "2 searches · 1 file · 1 command" — derived from the steps, never
    /// invented. The same file touched twice is one file. Core has no bundle
    /// to look strings up in, so the language arrives as a parameter.
    public static func summary(
        _ steps: [JobStepInfo], _ language: AppLanguage = .en
    ) -> String? {
        var searches = 0
        var pages = 0
        var commands = 0
        var files: Set<String> = []
        for step in steps {
            switch step.tool {
            case "WebSearch": searches += 1
            case "WebFetch": pages += 1
            case "Bash": commands += 1
            case "Read", "Write", "Edit", "NotebookEdit":
                if let path = path(of: step) {
                    files.insert((path as NSString).lastPathComponent)
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
    public static func files(_ steps: [JobStepInfo]) -> [String] {
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
    public static func worked(
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
