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

    /// "2 búsquedas · 1 archivo · 1 comando" — derived from the steps, never
    /// invented. The same file touched twice is one file.
    public static func summary(_ steps: [JobStepInfo]) -> String? {
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
        var parts: [String] = []
        if searches > 0 { parts.append(count(searches, "búsqueda", "búsquedas")) }
        if pages > 0 { parts.append(count(pages, "página", "páginas")) }
        if !files.isEmpty {
            parts.append(count(files.count, "archivo", "archivos"))
        }
        if commands > 0 { parts.append(count(commands, "comando", "comandos")) }
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

    /// "Trabajó 47 s" / "Trabajó 1:42". Nobody reads "Trabajó 102 s".
    public static func worked(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        guard total >= 60 else { return "Trabajó \(total) s" }
        return "Trabajó \(total / 60):\(String(format: "%02d", total % 60))"
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
