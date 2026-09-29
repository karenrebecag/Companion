import AppKit
import CompanionCore
import Foundation

/// Excel and Numbers through Apple Events (spec 20 D5), from the app itself:
/// `osascript` stays banned for the specialist. Every value reaches the
/// script through `AppleScriptText`, never by string pasting.
public struct AppleEventSheets: SpreadsheetDriving {
    /// The system's "not allowed to send Apple Events" answer.
    static let notPermitted = -1743
    /// Ours: the app is open with no document.
    static let noDocument = 9001
    /// Ours: the workbook in front is not the one the write was approved for.
    static let workbookMoved = 9002

    public init() {}

    public func active() async -> SheetApp? {
        await MainActor.run {
            let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               let app = SheetApp.allCases.first(where: { $0.bundleID == front }) {
                return app
            }
            return SheetApp.allCases.first { running.contains($0.bundleID) }
        }
    }

    public func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] {
        let result = try await run(Self.readScript(app, range: range))
        return Self.rows(result, range: range, app: app)
    }

    public func workbook(_ app: SheetApp) async throws -> String {
        let document = try await run(Self.pathScript(app)).stringValue ?? ""
        // An unsaved workbook has no file to copy; writing without a copy is
        // exactly what the backup rule exists to prevent.
        guard document.hasPrefix("/") else { throw SheetError.unsavedDocument }
        return document
    }

    public func write(
        _ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook approved: String
    ) async throws -> SheetWriteReceipt {
        // Resolved once: the backup is of the workbook the sheet named, and the
        // write script re-checks that same path in its own Apple Event.
        guard try await workbook(app) == approved else { throw SheetError.workbookChanged }
        let backup = SheetBackup.path(for: approved, at: Date())
        do {
            try FileManager.default.copyItem(atPath: approved, toPath: backup)
        } catch {
            Log.app("sheets: backup copy failed")
            throw SheetError.appFailed
        }
        _ = try await run(Self.writeScript(app, range: range, cells: cells, workbook: approved))
        let readBack = Self.rows(try await run(Self.readScript(app, range: range, workbook: approved)),
                                 range: range, app: app)
        return SheetWriteReceipt(backupPath: backup, readBack: readBack)
    }

    // MARK: - Scripts

    /// `workbook`: the check runs in the same script as `body`, so no other
    /// Apple Event can change the front workbook between them (M7).
    static func tell(_ app: SheetApp, workbook: String? = nil, _ body: String) -> String {
        // Excel calls its documents workbooks.
        let documents = app == .excel ? "workbooks" : "documents"
        var pin = ""
        if let workbook {
            pin = "\nif (\(pathExpression(app))) is not \(AppleScriptText.literal(workbook)) "
                + "then error number \(workbookMoved)"
        }
        return "tell application id \(AppleScriptText.literal(app.bundleID))\n"
            + "if (count of \(documents)) is 0 then error number \(noDocument)" + pin + "\n" + body + "\nend tell"
    }

    private static func pathExpression(_ app: SheetApp) -> String {
        switch app {
        case .excel: "full name of active workbook"
        case .numbers: "POSIX path of ((file of front document) as alias)"
        }
    }

    static func target(_ app: SheetApp) -> String {
        switch app {
        case .excel: "active sheet"
        case .numbers: "table 1 of active sheet of front document"
        }
    }

    static func pathScript(_ app: SheetApp) -> String {
        switch app {
        case .excel: tell(app, "return \(pathExpression(app))")
        case .numbers: tell(app, "return \(pathExpression(app))")
        }
    }

    static func readScript(_ app: SheetApp, range: SheetRange, workbook: String? = nil) -> String {
        let name = AppleScriptText.literal(range.a1)
        switch app {
        case .excel: return tell(app, workbook: workbook, "return value of range \(name) of \(target(app))")
        case .numbers: return tell(app, workbook: workbook, "return value of cells of range \(name) of \(target(app))")
        }
    }

    /// Excel takes the whole rectangle in one event; Numbers has no range
    /// setter, so it gets one statement per cell inside a single script.
    static func writeScript(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) -> String {
        switch app {
        case .excel:
            return tell(app, workbook: workbook,
                        "set formula of range \(AppleScriptText.literal(range.a1)) of \(target(app)) to "
                            + AppleScriptText.matrix(cells))
        case .numbers:
            var lines = ["tell \(target(app))"]
            for (r, row) in cells.enumerated() {
                for (c, cell) in row.enumerated() {
                    lines.append("set value of cell \(AppleScriptText.literal(range.cell(row: r, column: c))) to "
                        + AppleScriptText.value(cell))
                }
            }
            lines.append("end tell")
            return tell(app, workbook: workbook, lines.joined(separator: "\n"))
        }
    }

    // MARK: - Running

    static func sheetError(forCode code: Int) -> SheetError {
        switch code {
        case notPermitted: .needsPermission
        case noDocument: .noOpenDocument
        case workbookMoved: .workbookChanged
        default: .appFailed
        }
    }

    @MainActor
    private static func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw SheetError.appFailed }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            Log.app("sheets: apple event failed \(code)")
            throw sheetError(forCode: code)
        }
        return result
    }

    private func run(_ source: String) async throws -> SendableDescriptor {
        try await MainActor.run { SendableDescriptor(try Self.execute(source)) }
    }

    /// A descriptor is immutable once returned; it only crosses back from
    /// the main actor to be read.
    struct SendableDescriptor: @unchecked Sendable {
        let value: NSAppleEventDescriptor
        init(_ value: NSAppleEventDescriptor) { self.value = value }
        var stringValue: String? { Self.text(value) }

        static func text(_ descriptor: NSAppleEventDescriptor) -> String? {
            if descriptor.descriptorType == typeNull { return "" }
            if let text = descriptor.stringValue { return text }
            return descriptor.coerce(toDescriptorType: typeUnicodeText)?.stringValue
        }
    }

    /// Excel answers a list of rows, a single row, or a scalar; Numbers a flat list.
    static func rows(_ result: SendableDescriptor, range: SheetRange, app: SheetApp) -> [[String]] {
        let descriptor = result.value
        guard descriptor.numberOfItems > 0, descriptor.descriptorType == typeAEList else {
            return [[SendableDescriptor.text(descriptor) ?? ""]]
        }
        let items = (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) }
        if let first = items.first, first.descriptorType == typeAEList {
            return items.map { row in
                row.numberOfItems == 0 ? [] : (1...row.numberOfItems).map {
                    row.atIndex($0).flatMap(SendableDescriptor.text) ?? ""
                }
            }
        }
        let flat = items.map { SendableDescriptor.text($0) ?? "" }
        return app == .numbers || range.rows > 1 ? SheetValues.reshape(flat, columns: range.columns) : [flat]
    }
}
