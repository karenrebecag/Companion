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
            // Fail-open: a snapshot that cannot be made never stops the save.
            let previous = versions?.snapshot(realPath, trigger: .preSave) ?? .noPrevious
            let receipt = try await documents.render(spec, format: format, to: URL(fileURLWithPath: realPath))
            // Verified on disk before anything is reported (Incredible's rule too).
            guard FileManager.default.fileExists(atPath: realPath), receipt.bytes > 0 else {
                return ToolResult(ok: false, output: "The document was not written")
            }
            let pages = receipt.pages.map { ", \($0) page\($0 == 1 ? "" : "s")" } ?? ""
            Log.app("document: \(format.rawValue) blocks=\(spec.blocks.count) bytes=\(receipt.bytes)")
            _ = versions?.snapshot(realPath, trigger: .postSave)
            return ToolResult(ok: true, output: "Created \(realPath)\(pages), \(receipt.bytes) bytes"
                + Self.versionNote(previous))
        } catch DocumentError.unsupportedFormat {
            return ToolResult(ok: false, output: "invalid_args: that format is not supported")
        } catch {
            Log.app("document: render failed")
            return ToolResult(ok: false, output: "The document could not be rendered")
        }
    }

    /// What the model is told about the copy made before a save. Never a path: the
    /// store is private to the app and the model has no business reading it.
    static func versionNote(_ outcome: FileVersions.Outcome) -> String {
        switch outcome {
        case .saved: "; a previous version was kept"
        case .noPrevious: ""
        case .tooLarge: "; no previous version could be kept (it is over the "
            + "\(FileVersions.defaultMaxBytes / 1024 / 1024) MB limit)"
        case .failed: "; no previous version could be kept"
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
            // The workbook the sheet named is the only one that may be written;
            // one that was never named (no sheet bound it) is refused too.
            guard let approved = SheetApproval.workbook(in: arguments),
                  try await sheets.workbook(app) == approved else { throw SheetError.workbookChanged }
            // Companion never sends Save, so the file on disk only changes when the
            // user saves: one copy before the write is all there is to keep.
            let previous = versions?.snapshot(approved, trigger: .preSave) ?? .noPrevious
            let receipt = try await sheets.write(app, range: range, cells: cells, workbook: approved)
            Log.app("sheets: wrote \(app.rawValue) cells=\(range.rows * range.columns)")
            guard !receipt.readBackUnavailable else {
                return ToolResult(ok: true, output: "Wrote \(range.a1) in \(app.rawValue), but the result could not "
                    + "be read back: the workbook in front changed right after the write. Check the sheet"
                    + Self.versionNote(previous))
            }
            return ToolResult(ok: true, output: "Wrote \(range.a1) in \(app.rawValue)"
                + Self.versionNote(previous) + ".\nRead back:\n" + Self.render(receipt.readBack, range: range, app: app))
        } catch {
            return Self.failure(error)
        }
    }

    /// The arguments as the approval sheet must show them: the workbook and app
    /// that a write would land in, resolved by the runner now. The same JSON
    /// is what runs, so approving and writing name one workbook.
    func approvalArguments(tool: String, json: String) async -> String {
        guard tool == NativeTool.sheetWrite.rawValue else { return json }
        // Whatever cannot be resolved below leaves no model-supplied workbook behind.
        guard let sheets, let object = ToolArguments.parse(json),
              let app = await sheetApp(object, sheets) else { return SheetApproval.bind(json, workbook: nil) }
        var workbook: String?
        do {
            workbook = try await sheets.workbook(app)
        } catch {
            Log.app("sheets: workbook not resolved for approval")
        }
        return SheetApproval.bind(json, workbook: workbook, app: app)
    }

    func sheetApp(_ arguments: [String: Any], _ sheets: any SpreadsheetDriving) async -> SheetApp? {
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
        case .forbiddenFormula?: code = "invalid_args: only plain spreadsheet formulas are allowed: no web fetches, external references or commands"
        case .invalidValues?: code = "invalid_args: values must be JSON rows of text, numbers or null"
        case .noOpenDocument?: code = noSheet.output
        case .workbookChanged?: code = "workbook_changed: the workbook in front is not the one that was approved; nothing was written"
        case .unsavedDocument?: code = "unsaved_document: ask the user to save the workbook once, so it can be identified and a previous version kept"
        case .needsPermission?: code = BridgeCode.permissionRequired + ": " + BridgeMessages.automationRequired
        case .appFailed?, nil: code = "app_failed: the spreadsheet app did not accept the command"
        }
        return ToolResult(ok: false, output: code)
    }
}
