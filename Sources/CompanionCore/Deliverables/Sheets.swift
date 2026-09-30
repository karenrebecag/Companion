import Foundation

// Wave 20-3 (spec 20 D5): Excel and Numbers, live, through Apple Events from
// the app — what xlwings does on a Mac. Everything that decides lives here;
// the adapter only sends the script.

public enum SheetApp: String, Sendable, Equatable, CaseIterable {
    case excel, numbers

    public var bundleID: String {
        switch self {
        case .excel: "com.microsoft.Excel"
        case .numbers: "com.apple.iWork.Numbers"
        }
    }
}

/// A rectangle in A1 notation, on the active sheet. No sheet prefix: the
/// user is looking at the sheet it acts on.
public struct SheetRange: Sendable, Equatable {
    /// A bigger write is a file job, not a live edit (Incredible: 5-30 ms per
    /// cell over Apple Events on a Mac).
    public static let maxCells = 5_000
    static let maxRow = 1_048_576
    static let maxColumn = 16_384

    public let firstColumn: Int
    public let firstRow: Int
    public let lastColumn: Int
    public let lastRow: Int

    public var rows: Int { lastRow - firstRow + 1 }
    public var columns: Int { lastColumn - firstColumn + 1 }

    public var a1: String {
        let start = Self.name(firstColumn) + "\(firstRow)"
        return rows == 1 && columns == 1 ? start : start + ":" + Self.name(lastColumn) + "\(lastRow)"
    }

    public init?(a1 raw: String) {
        let parts = raw.uppercased().split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              let start = Self.cell(String(parts[0])),
              let end = parts.count == 2 ? Self.cell(String(parts[1])) : start else { return nil }
        firstColumn = min(start.column, end.column)
        lastColumn = max(start.column, end.column)
        firstRow = min(start.row, end.row)
        lastRow = max(start.row, end.row)
        guard rows * columns <= Self.maxCells else { return nil }
    }

    /// The A1 name of a cell inside the range, zero-based from its corner.
    public func cell(row: Int, column: Int) -> String {
        Self.name(firstColumn + column) + "\(firstRow + row)"
    }

    private static func cell(_ text: String) -> (column: Int, row: Int)? {
        let letters = text.prefix { $0.isASCII && $0.isLetter }
        let digits = text.dropFirst(letters.count)
        guard (1...3).contains(letters.count), !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let row = Int(digits), (1...maxRow).contains(row) else { return nil }
        let column = letters.reduce(0) { $0 * 26 + Int($1.asciiValue! - 64) }
        guard column <= maxColumn else { return nil }
        return (column, row)
    }

    static func name(_ column: Int) -> String {
        var n = column
        var out = ""
        while n > 0 {
            let r = (n - 1) % 26
            out = String(UnicodeScalar(UInt8(65 + r))) + out
            n = (n - 1) / 26
        }
        return out
    }
}

public enum SheetCell: Sendable, Equatable {
    case text(String)
    case number(Double)
    case formula(String)
    case empty
}

public enum SheetError: Error, Sendable, Equatable {
    case invalidRange
    case shapeMismatch
    case forbiddenFormula
    case invalidValues
    case noOpenDocument
    case unsavedDocument
    case workbookChanged
    case needsPermission
    case appFailed
}

public enum SheetValues {
    /// A range holds at most `SheetRange.maxCells` (5 000) cells; 1 MiB is
    /// about 200 bytes a cell, room for long text and formulas and nothing
    /// like the memory a hostile array could ask for.
    public static let maxSheetBytes = 1024 * 1024
    /// A 2-D array, sent as JSON text or as a real array, that must match the
    /// range cell for cell: a short write would land shifted.
    public static func parse(any value: Any?, for range: SheetRange) -> Result<[[SheetCell]], SheetError> {
        let raw: Any?
        if let text = value as? String {
            guard text.utf8.count <= maxSheetBytes else { return .failure(.invalidValues) }
            raw = CompanionBlocks.jsonArray(text)
        } else {
            raw = value
        }
        guard let rows = raw as? [Any] else { return .failure(.invalidValues) }
        guard rows.count == range.rows else { return .failure(.shapeMismatch) }
        var out: [[SheetCell]] = []
        for row in rows {
            guard let cells = row as? [Any] else { return .failure(.invalidValues) }
            guard cells.count == range.columns else { return .failure(.shapeMismatch) }
            var line: [SheetCell] = []
            for cell in cells {
                guard let parsed = parse(cell) else { return .failure(.invalidValues) }
                if case .text(let text) = parsed, looksLikeFormula(text), !FormulaPolicy.isAllowedSigned(text) {
                    return .failure(.forbiddenFormula)
                }
                if case .formula(let formula) = parsed, !FormulaPolicy.isAllowed(formula) {
                    return .failure(.forbiddenFormula)
                }
                line.append(parsed)
            }
            out.append(line)
        }
        return .success(out)
    }

    static func parse(_ cell: Any) -> SheetCell? {
        if cell is NSNull { return .empty }
        if let number = CompanionBlocks.jsonDouble(cell) { return number.isFinite ? .number(number) : nil }
        guard let text = cell as? String else { return nil }
        if text.isEmpty { return .empty }
        return text.hasPrefix("=") ? .formula(text) : .text(text)
    }

    /// Excel's formula setter, like typing, starts a formula on any of these;
    /// the cell stays text for us but must pass the same list.
    public static func looksLikeFormula(_ text: String) -> Bool {
        guard let first = text.first(where: { !$0.isWhitespace }) else { return false }
        return "=+-@".contains(foldedSign(first) ?? first)
    }

    /// Excel reads fullwidth signs as the ASCII ones; the raw character would
    /// let `＝IMAGE(...)` skip the gate.
    static func foldedSign(_ char: Character) -> Character? {
        String(char).precomposedStringWithCompatibilityMapping.first
    }

    /// Numbers reads a range as one flat list.
    // HACK: a short read is padded with blanks, so a cell Numbers dropped reads
    // as empty. Compare counts against the range when a write report must be exact.
    public static func reshape(_ flat: [String], columns: Int) -> [[String]] {
        guard columns > 0 else { return [] }
        var rows: [[String]] = []
        var index = 0
        repeat {
            let row = Array(flat[min(index, flat.count)..<min(index + columns, flat.count)])
            rows.append(row + Array(repeating: "", count: columns - row.count))
            index += columns
        } while index < flat.count
        return rows
    }

    /// The sheet says where and what, not "sheet_write".
    public static func approvalDetail(_ object: [String: Any]) -> String? {
        guard let range = object["range"] as? String else { return nil }
        let app = (object["app"] as? String).map { $0 + " · " } ?? ""
        return app + range.uppercased() + "\n" + SheetApproval.preview(object, language: .en)
    }
}

public enum AppleScriptText {
    /// A string literal that stays one literal: quotes and backslashes
    /// escaped, line breaks turned into the escapes AppleScript reads.
    public static func literal(_ text: String) -> String {
        var out = "\""
        for char in text {
            switch char {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n", "\r\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(char)
            }
        }
        return out + "\""
    }

    public static func value(_ cell: SheetCell) -> String {
        switch cell {
        case .text(let text), .formula(let text): literal(text)
        case .number(let number): DataCells.number(number)
        case .empty: "\"\""
        }
    }

    public static func matrix(_ cells: [[SheetCell]]) -> String {
        "{" + cells.map { "{" + $0.map(value).joined(separator: ", ") + "}" }.joined(separator: ", ") + "}"
    }
}

public enum SheetBackup {
    /// Next to the workbook, same extension, so it opens the same way. A name
    /// already taken gets `-2`, `-3`...: two writes in one second must not
    /// refuse or overwrite each other's copy.
    public static func path(
        for document: String, at date: Date,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        let url = URL(fileURLWithPath: document)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = url.deletingPathExtension().lastPathComponent + "-backup-" + formatter.string(from: date)
        let folder = url.deletingLastPathComponent()
        func candidate(_ name: String) -> String {
            folder.appendingPathComponent(name).appendingPathExtension(url.pathExtension).path
        }
        var backup = candidate(stem)
        var attempt = 2
        while exists(backup) {
            backup = candidate(stem + "-\(attempt)")
            attempt += 1
        }
        return backup
    }
}

public struct SheetWriteReceipt: Sendable, Equatable {
    public var backupPath: String
    /// A sample read back after the write, for the report.
    public var readBack: [[String]]
    /// The write happened but the workbook in front changed before it could be
    /// read back: the report must not say "nothing was written".
    public var readBackUnavailable: Bool

    public init(backupPath: String, readBack: [[String]], readBackUnavailable: Bool = false) {
        self.backupPath = backupPath
        self.readBack = readBack
        self.readBackUnavailable = readBackUnavailable
    }
}

/// Port for `sheet_read` / `sheet_write`: one adapter per app behind it.
public protocol SpreadsheetDriving: Sendable {
    /// The app whose document the user is looking at, if any.
    func active() async -> SheetApp?
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]]
    /// The saved file of the workbook in front, resolved once so the sheet, the
    /// backup and the write all name the same one.
    func workbook(_ app: SheetApp) async throws -> String
    /// `workbook` is what the user approved: the write aborts, untouched, if
    /// the app no longer has that one in front.
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt
}
