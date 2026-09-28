import CompanionCore
import Foundation

// Wave 20-2/20-3: create_document, sheet_read, sheet_write. The same write
// barrier as write_file; the model reads a receipt, never the file.

extension NativeToolRunner {
    func createDocument(arguments: [String: Any]) async -> ToolResult {
        guard let documents else { return ToolResult(ok: false, output: "Documents are unavailable") }
        guard let path = arguments["path"] as? String, let format = DocumentFormat(path: path) else {
            return ToolResult(ok: false, output: "invalid_args: path must end in .pdf or .xlsx")
        }
        guard let spec = DocumentSpec.parse(any: arguments["document"]) else {
            return ToolResult(ok: false, output: "invalid_args: document must be JSON with a title and blocks")
        }
        let realPath: String
        switch writeBarrier(path) {
        case .success(let resolved): realPath = resolved
        case .failure(let refused): return refused
        }
        do {
            try FileManager.default.createDirectory(
                atPath: (realPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            let receipt = try await documents.render(spec, format: format, to: URL(fileURLWithPath: realPath))
            // Verified on disk before anything is reported (Incredible's rule too).
            guard FileManager.default.fileExists(atPath: realPath), receipt.bytes > 0 else {
                return ToolResult(ok: false, output: "The document was not written")
            }
            let pages = receipt.pages.map { ", \($0) page\($0 == 1 ? "" : "s")" } ?? ""
            Log.app("document: \(format.rawValue) blocks=\(spec.blocks.count) bytes=\(receipt.bytes)")
            return ToolResult(ok: true, output: "Created \(realPath)\(pages), \(receipt.bytes) bytes")
        } catch DocumentError.unsupportedFormat {
            return ToolResult(ok: false, output: "invalid_args: that format is not supported")
        } catch {
            Log.app("document: render failed")
            return ToolResult(ok: false, output: "The document could not be rendered")
        }
    }

    func sheetRead(arguments: [String: Any]) async -> ToolResult {
        guard let sheets else { return ToolResult(ok: false, output: "Spreadsheets are unavailable") }
        guard let range = (arguments["range"] as? String).flatMap(SheetRange.init(a1:)) else {
            return ToolResult(ok: false, output: "invalid_args: range must be A1 notation, at most "
                + "\(SheetRange.maxCells) cells")
        }
        guard let app = await sheetApp(arguments, sheets) else { return Self.noSheet }
        do {
            let rows = try await sheets.read(app, range: range)
            Log.app("sheets: read \(app.rawValue) cells=\(range.rows * range.columns)")
            return ToolResult(ok: true, output: Self.render(rows, range: range, app: app))
        } catch {
            return Self.failure(error)
        }
    }

    func sheetWrite(arguments: [String: Any]) async -> ToolResult {
        guard let sheets else { return ToolResult(ok: false, output: "Spreadsheets are unavailable") }
        guard let range = (arguments["range"] as? String).flatMap(SheetRange.init(a1:)) else {
            return ToolResult(ok: false, output: "invalid_args: range must be A1 notation, at most "
                + "\(SheetRange.maxCells) cells")
        }
        let cells: [[SheetCell]]
        switch SheetValues.parse(any: arguments["values"], for: range) {
        case .success(let parsed): cells = parsed
        case .failure(let error): return Self.failure(error)
        }
        guard let app = await sheetApp(arguments, sheets) else { return Self.noSheet }
        do {
            let receipt = try await sheets.write(app, range: range, cells: cells)
            Log.app("sheets: wrote \(app.rawValue) cells=\(range.rows * range.columns)")
            return ToolResult(ok: true, output: "Wrote \(range.a1) in \(app.rawValue). Backup of the saved "
                + "workbook: \(receipt.backupPath)\nRead back:\n" + Self.render(receipt.readBack, range: range, app: app))
        } catch {
            return Self.failure(error)
        }
    }

    private func sheetApp(_ arguments: [String: Any], _ sheets: any SpreadsheetDriving) async -> SheetApp? {
        if let named = (arguments["app"] as? String)?.lowercased(), let app = SheetApp(rawValue: named) {
            return app
        }
        return await sheets.active()
    }

    static let noSheet = ToolResult(ok: false, output: "no_open_document: open the workbook in Excel or Numbers first")
    /// Enough to check a write; the rest stays in the workbook.
    static let readBackCells = 200

    static func render(_ rows: [[String]], range: SheetRange, app: SheetApp) -> String {
        var budget = readBackCells
        var lines: [String] = []
        for (r, row) in rows.enumerated() {
            guard budget > 0 else { lines.append("…"); break }
            let cells = row.prefix(budget)
            budget -= cells.count
            lines.append("\(range.firstRow + r): " + cells.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }

    static func failure(_ error: Error) -> ToolResult {
        let code: String
        switch error as? SheetError {
        case .invalidRange?: code = "invalid_args: range"
        case .shapeMismatch?: code = "invalid_args: values must have exactly the rows and columns of the range"
        case .forbiddenFormula?: code = "invalid_args: formulas that fetch from the web or run commands are not allowed"
        case .invalidValues?: code = "invalid_args: values must be JSON rows of text, numbers or null"
        case .noOpenDocument?: code = noSheet.output
        case .unsavedDocument?: code = "unsaved_document: ask the user to save the workbook once, so a backup can be made"
        case .needsPermission?: code = "needs_permission: allow Companion to control the app in System Settings > "
            + "Privacy & Security > Automation"
        case .appFailed?, nil: code = "app_failed: the spreadsheet app did not accept the command"
        }
        return ToolResult(ok: false, output: code)
    }
}
