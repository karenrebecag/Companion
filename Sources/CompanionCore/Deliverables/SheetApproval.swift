import CryptoKit
import Foundation

/// Wave 20c D4 (H4): what a `sheet_write` approval names and shows. The
/// workbook comes from the runner that will write to it, never from the
/// model's arguments, and the values are shown whole: a sheet that cuts them
/// approves cells the user never saw.
package enum SheetApproval {
    /// The key the runner sets in the arguments it puts in front of the user.
    static let workbookKey = "workbook"

    package static func workbook(in arguments: [String: Any]) -> String? {
        guard let path = arguments[workbookKey] as? String, path.hasPrefix("/") else { return nil }
        return path
    }

    /// The arguments with the runner's workbook, or with none: a value the
    /// model put there must not pass for the one the runner resolved.
    /// `app` pins the one the runner resolved when the model left it out, so
    /// the write cannot land in whatever is in front later.
    package static func bind(_ inputJSON: String, workbook: String?, app: SheetApp? = nil) -> String {
        guard var object = ToolArguments.parse(inputJSON) else { return "{}" }
        object[workbookKey] = workbook
        if let app { object["app"] = app.rawValue }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            // The model's own text must not reach the sheet as if bound.
            return "{}"
        }
    }

    /// Stable over the exact cells, types and their boundaries: it is what a
    /// remembered decision covers.
    package static func fingerprint(_ cells: [[SheetCell]]) -> String {
        var canonical = "\(cells.count)"
        for row in cells {
            canonical += "|\(row.count)"
            for cell in row {
                switch cell {
                case .text(let text): canonical += ";t\(text.utf8.count):\(text)"
                case .formula(let text): canonical += ";f\(text.utf8.count):\(text)"
                case .number(let number): canonical += ";n\(number.bitPattern)"
                case .empty: canonical += ";e"
                }
            }
        }
        return SHA256.hash(data: Data(canonical.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Workbook, range with its cell count, then every cell as it will be
    /// typed. Values that do not parse are shown raw: the write will refuse
    /// them, and the sheet still says what was asked.
    package static func preview(_ arguments: [String: Any], language: AppLanguage) -> String {
        let es = language == .es
        var lines = [workbook(in: arguments) ?? (es ? "Libro sin identificar" : "Workbook not identified")]
        guard let range = (arguments["range"] as? String).flatMap(SheetRange.init(a1:)) else { return lines[0] }
        let count = range.rows * range.columns
        lines.append("\(range.a1) · \(count) " + (es ? "celdas" : "cells"))
        if case .success(let cells) = SheetValues.parse(any: arguments["values"], for: range) {
            lines += cells.map { $0.map(shown).joined(separator: " | ") }
        } else if let text = arguments["values"] as? String {
            lines.append(escaped(text))
        } else if let raw = arguments["values"] {
            lines.append(escaped("\(raw)"))
        }
        return lines.joined(separator: "\n")
    }

    /// A row is one line and a cell has no bare `|`, so a value cannot forge
    /// rows or cells; invisible characters (bidi overrides) are spelled out.
    private static func escaped(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "|": out += "\\|"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if [.format, .control, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory) {
                    out += "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    private static func shown(_ cell: SheetCell) -> String {
        switch cell {
        case .text(let text), .formula(let text): escaped(text)
        case .number(let number): DataCells.number(number)
        case .empty: ""
        }
    }
}
