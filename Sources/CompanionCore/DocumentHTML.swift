import Foundation

/// The one template (spec 20 D3/D4): blocks in, a self-contained page out.
/// Every string passes through `escape`; the only markup is ours.
public enum DocumentHTML {
    public static func render(_ spec: DocumentSpec) -> String {
        var body = ""
        let hasCover = spec.blocks.contains { if case .cover = $0 { true } else { false } }
        if !hasCover {
            body += "<header><h1>\(escape(spec.title))</h1>"
                + (spec.subtitle.map { "<p class=\"sub\">\(escape($0))</p>" } ?? "") + "</header>"
        }
        for block in spec.blocks { body += html(block) }
        return "<!doctype html><html><head><meta charset=\"utf-8\"><title>\(escape(spec.title))</title>"
            + "<style>\(css)</style></head><body>\(body)</body></html>"
    }

    private static func html(_ block: DocumentSpec.Block) -> String {
        switch block {
        case .cover(let title, let subtitle, let date):
            return "<section class=\"cover\"><h1>\(escape(title))</h1>"
                + (subtitle.map { "<p class=\"sub\">\(escape($0))</p>" } ?? "")
                + (date.map { "<p class=\"date\">\(escape($0))</p>" } ?? "") + "</section>"
        case .heading(let text, let level):
            let tag = "h\(level + 1)"
            return "<\(tag)>\(escape(text))</\(tag)>"
        case .paragraph(let text):
            return text.components(separatedBy: "\n\n").map { "<p>\(escape($0))</p>" }.joined()
        case .bullets(let items):
            return "<ul>" + items.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
        case .stats(let stats):
            return title(stats.title) + "<div class=\"stats\">" + stats.items.map { item in
                "<div class=\"stat\"><div class=\"v\">\(escape(item.value))"
                    + (item.delta.map { "<span class=\"d \(tone($0))\">\(escape($0))</span>" } ?? "")
                    + "</div><div class=\"l\">\(escape(item.label))</div></div>"
            }.joined() + "</div>"
        case .table(let table):
            return title(table.title) + tableHTML(table)
        case .chart(let chart):
            return "<figure>" + title(chart.title, unit: chart.unit) + ChartSVG.render(chart) + "</figure>"
        case .callout(let text, let tone):
            return "<aside class=\"callout \(tone.rawValue)\">\(escape(text))</aside>"
        case .divider:
            return "<hr>"
        }
    }

    private static func title(_ text: String?, unit: String? = nil) -> String {
        guard let text, !text.isEmpty else { return "" }
        return "<h4>\(escape(text))" + (unit.map { " <span class=\"unit\">\(escape($0))</span>" } ?? "") + "</h4>"
    }

    private static func tone(_ delta: String) -> String {
        let first = delta.trimmingCharacters(in: .whitespaces).first
        if first == "+" { return "up" }
        if first == "-" || first == "\u{2212}" { return "down" }
        return ""
    }

    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for char in text {
            switch char {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(char)
            }
        }
        return out
    }

    /// HACK: WebKit's print path slices the page and ignores a repeating
    /// `thead` (measured: page 2 opens on a data row), so a long table is cut
    /// into chunks that each carry the header and never split. Sized for ~28
    /// single-line rows per A4 page; a table of wrapped rows can still overflow
    /// a chunk. Replace with real header repetition if the renderer honors it.
    static let rowsPerChunk = 20

    private static func tableHTML(_ table: TableBlock) -> String {
        let head = "<thead><tr>" + table.columns.map { "<th>\(escape($0))</th>" }.joined() + "</tr></thead>"
        let rows = table.rows.map { "<tr>" + $0.map { "<td>\(escape($0))</td>" }.joined() + "</tr>" }
        guard !rows.isEmpty else { return "<table>\(head)<tbody></tbody></table>" }
        return stride(from: 0, to: rows.count, by: rowsPerChunk).map { start in
            "<table>\(head)<tbody>"
                + rows[start..<min(start + rowsPerChunk, rows.count)].joined() + "</tbody></table>"
        }.joined()
    }

    /// A4 with print margins; rows and figures never split across pages.
    static let css = """
    @page { size: A4; margin: 18mm 16mm; }
    * { box-sizing: border-box; }
    body { font-family: "Geist", -apple-system, "Helvetica Neue", sans-serif; color: #\(DocumentTheme.ink);
      font-size: 10.5pt; line-height: 1.5; margin: 0; }
    h1 { font-size: 24pt; line-height: 1.15; margin: 0 0 6pt; letter-spacing: -0.02em; }
    h2 { font-size: 16pt; margin: 18pt 0 6pt; } h3 { font-size: 13pt; margin: 14pt 0 4pt; }
    h4 { font-size: 11pt; margin: 12pt 0 6pt; } .unit { color: #\(DocumentTheme.muted); font-weight: 400; }
    .sub { color: #\(DocumentTheme.muted); font-size: 12pt; margin: 0; } .date { color: #\(DocumentTheme.muted); }
    header { margin-bottom: 16pt; }
    .cover { min-height: 60vh; display: flex; flex-direction: column; justify-content: flex-end;
      border-bottom: 1px solid #\(DocumentTheme.border); padding-bottom: 18pt; margin-bottom: 18pt; }
    .cover h1 { font-size: 34pt; }
    .stats { display: flex; flex-wrap: wrap; gap: 10pt; margin: 6pt 0 12pt; }
    .stat { flex: 1 1 120pt; background: #\(DocumentTheme.surface); border: 1px solid #\(DocumentTheme.border);
      border-radius: 8pt; padding: 10pt; break-inside: avoid; }
    .stat .v { font-size: 18pt; font-weight: 600; } .stat .l { color: #\(DocumentTheme.muted); font-size: 9pt; }
    .d { font-size: 9pt; margin-left: 6pt; } .d.up { color: #\(DocumentTheme.success); } .d.down { color: #\(DocumentTheme.danger); }
    table { width: 100%; border-collapse: collapse; margin: 6pt 0 12pt; font-size: 9.5pt; }
    table { break-inside: avoid; } table + table { margin-top: 0; }
    thead { display: table-header-group; } tr { break-inside: avoid; }
    th { text-align: left; color: #\(DocumentTheme.muted); font-weight: 600; border-bottom: 1px solid #\(DocumentTheme.ink); padding: 5pt 6pt; }
    td { border-bottom: 1px solid #\(DocumentTheme.border); padding: 5pt 6pt; }
    figure { margin: 8pt 0 14pt; break-inside: avoid; } svg .t { font-size: 10px; fill: #\(DocumentTheme.muted); }
    .callout { border-left: 3pt solid #\(DocumentTheme.link); background: #\(DocumentTheme.surface); padding: 8pt 10pt;
      margin: 10pt 0; break-inside: avoid; }
    .callout.success { border-color: #\(DocumentTheme.success); } .callout.warning { border-color: #\(DocumentTheme.warning); }
    .callout.danger { border-color: #\(DocumentTheme.danger); }
    hr { border: 0; border-top: 1px solid #\(DocumentTheme.border); margin: 14pt 0; }
    ul { padding-left: 16pt; } li { margin: 2pt 0; }
    """
}
