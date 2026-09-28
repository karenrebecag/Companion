import Foundation

/// Wave 20: the three tool contracts. Nested data travels as JSON text: an
/// `array` schema without `items` is refused by some providers, and a string
/// works with every one of them.
enum DeliverableTools {
    static func spec(_ tool: NativeTool) -> ToolSpec {
        switch tool {
        case .createDocument:
            return ToolSpec(
                name: "create_document",
                description: "Create a finished file the user can open: a PDF report, one-pager or "
                    + "receipt, or an .xlsx workbook. You choose the content as blocks; the look is "
                    + "fixed by the template, so never write HTML or styling. Blocks: "
                    + "{\"type\":\"cover\",\"title\",\"subtitle\",\"date\"}, {\"type\":\"heading\",\"text\",\"level\":1-3}, "
                    + "{\"type\":\"paragraph\",\"text\"}, {\"type\":\"bullets\",\"items\":[...]}, "
                    + "{\"type\":\"stats\",\"items\":[{\"label\",\"value\",\"delta\"}]}, "
                    + "{\"type\":\"table\",\"title\",\"columns\":[...],\"rows\":[[...]]}, "
                    + "{\"type\":\"chart\",\"title\",\"kind\":\"bar|line|area|pie|donut|scatter\",\"unit\","
                    + "\"labels\":[...],\"series\":[{\"name\",\"values\":[...]}]}, "
                    + "{\"type\":\"callout\",\"text\",\"tone\":\"info|success|warning|danger\"}, {\"type\":\"divider\"}. "
                    + "For .xlsx, every table block becomes a sheet. Only figures you looked up or were given.",
                properties: [
                    ToolProperty(name: "path", type: "string",
                                 description: "where to save, ending in .pdf or .xlsx"),
                    ToolProperty(name: "document", type: "string",
                                 description: "JSON text: {\"title\",\"subtitle\",\"blocks\":[...]}"),
                ],
                required: ["path", "document"])
        case .sheetRead:
            return ToolSpec(
                name: "sheet_read",
                description: "Read cells from the spreadsheet open in Excel or Numbers right now, on "
                    + "its active sheet (Numbers: its first table). Use before writing.",
                properties: [
                    ToolProperty(name: "range", type: "string", description: "A1 range, e.g. A1:D20"),
                    ToolProperty(name: "app", type: "string",
                                 description: "excel or numbers; omit to use the one in front"),
                ],
                required: ["range"])
        case .sheetWrite:
            return ToolSpec(
                name: "sheet_write",
                description: "Write values or formulas into the spreadsheet open in Excel or Numbers, "
                    + "in one rectangle. A copy of the saved workbook is made first and the cells are "
                    + "read back after. Formulas start with =; nothing that fetches from the web.",
                properties: [
                    ToolProperty(name: "range", type: "string", description: "A1 range, e.g. B2:D4"),
                    ToolProperty(name: "values", type: "string",
                                 description: "JSON text, rows of cells matching the range exactly, "
                                     + "e.g. [[\"Total\",\"=SUM(B2:B9)\"]]; null leaves a cell empty"),
                    ToolProperty(name: "app", type: "string",
                                 description: "excel or numbers; omit to use the one in front"),
                ],
                required: ["range", "values"])
        default:
            return ToolSpec(name: tool.rawValue, description: "", properties: [], required: [])
        }
    }
}

extension NativeTool {
    /// Offered by the parent itself (spec 20b D2): with Claude Code installed
    /// every delegation goes to it, and it has none of these.
    public static let parentDeliverables: [NativeTool] = [.createDocument, .sheetRead, .sheetWrite]
}

/// Tools the parent offers the user but never lends over the MCP bridge. The
/// approval memory is process-wide, so a "remember" given in the chat would
/// wave an agent's workbook writes through; and sheet_read, being safe, would
/// give it every open workbook without a sheet.
public enum BridgeScope {
    public static func isLocalOnly(_ name: String) -> Bool {
        NativeTool.parentDeliverables.contains { $0.rawValue == name }
    }
}

extension ParentTool {
    /// A pending sheet the parent asked for itself, as opposed to a job's.
    public static func ownsRequest(_ toolName: String) -> Bool {
        ParentTool(rawValue: toolName) != nil
            || NativeTool.parentDeliverables.contains { $0.rawValue == toolName }
    }
}
