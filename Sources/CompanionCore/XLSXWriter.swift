import Foundation

// Wave 20-4 (spec 20 D6): an .xlsx written in Swift. SpreadsheetML inside a
// zip; entries are stored, not deflated, which every reader accepts and
// keeps the writer free of a compression dependency.

/// A minimal zip: stored entries, CRC-32, one central directory.
public enum ZipWriter {
    static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    public static func archive(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        // 1980-01-01 00:00: a fixed stamp keeps the output reproducible.
        let time: UInt16 = 0
        let date: UInt16 = 0x21
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(out.count)
            out.le32(0x0403_4B50); out.le16(20); out.le16(0x0800); out.le16(0)
            out.le16(time); out.le16(date); out.le32(crc); out.le32(size); out.le32(size)
            out.le16(UInt16(name.count)); out.le16(0)
            out.append(name); out.append(entry.data)
            central.le32(0x0201_4B50); central.le16(20); central.le16(20); central.le16(0x0800); central.le16(0)
            central.le16(time); central.le16(date); central.le32(crc); central.le32(size); central.le32(size)
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0)
            central.le32(0); central.le32(offset)
            central.append(name)
        }
        let start = UInt32(out.count)
        out.append(central)
        out.le32(0x0605_4B50); out.le16(0); out.le16(0)
        out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(central.count)); out.le32(start); out.le16(0)
        return out
    }
}

extension Data {
    mutating func le16(_ value: UInt16) { append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)]) }
    mutating func le32(_ value: UInt32) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}

public enum XLSXWriter {
    public struct Sheet: Sendable, Equatable {
        public var name: String
        /// The first row is the header.
        public var rows: [[String]]
    }

    /// Stats, tables and charts, each as its own sheet, in document order.
    public static func sheets(_ spec: DocumentSpec) -> [Sheet] {
        var raw: [(title: String?, rows: [[String]])] = []
        for block in spec.blocks {
            switch block {
            case .stats(let stats):
                // Labels as the header, values under them: no word to translate.
                raw.append((stats.title, [stats.items.map(\.label), stats.items.map(\.value)]))
            case .table(let table):
                raw.append((table.title, [table.columns] + table.rows))
            case .chart(let chart):
                let table = chart.asTable
                raw.append((chart.title, [table.columns] + table.rows))
            default:
                continue
            }
        }
        let names = uniqueNames(raw.map { $0.title ?? "" })
        return zip(names, raw).map { Sheet(name: $0, rows: $1.rows) }
    }

    public static func package(_ spec: DocumentSpec) -> Data? {
        let sheets = sheets(spec)
        guard !sheets.isEmpty else { return nil }
        var entries: [(name: String, data: Data)] = [
            ("[Content_Types].xml", Data(contentTypes(sheets.count).utf8)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("xl/workbook.xml", Data(workbook(sheets).utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRels(sheets.count).utf8)),
            ("xl/styles.xml", Data(styles.utf8)),
        ]
        for (index, sheet) in sheets.enumerated() {
            entries.append(("xl/worksheets/sheet\(index + 1).xml", Data(sheetXML(sheet).utf8)))
        }
        return ZipWriter.archive(entries)
    }

    /// Excel's rules: 31 characters, none of : \ / ? * [ ], unique.
    public static func uniqueNames(_ titles: [String]) -> [String] {
        var used = Set<String>()
        return titles.enumerated().map { index, title in
            let cleaned = String(title.filter { !":\\/?*[]".contains($0) }
                .trimmingCharacters(in: .whitespaces).prefix(31))
            var name = cleaned.isEmpty ? "Hoja \(index + 1)" : cleaned
            var n = 2
            while used.contains(name.lowercased()) {
                let suffix = " (\(n))"
                name = String((cleaned.isEmpty ? "Hoja \(index + 1)" : cleaned).prefix(31 - suffix.count)) + suffix
                n += 1
            }
            used.insert(name.lowercased())
            return name
        }
    }

    public static func sheetXML(_ sheet: Sheet) -> String {
        let columnCount = sheet.rows.map(\.count).max() ?? 0
        let widths: [Int] = (0..<columnCount).map { column in
            let longest: Int = sheet.rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
            return min(60, max(8, longest) + 2)
        }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
            + "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" "
            + "activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>"
        if !widths.isEmpty {
            xml += "<cols>" + widths.enumerated().map {
                "<col min=\"\($0.offset + 1)\" max=\"\($0.offset + 1)\" width=\"\($0.element)\" customWidth=\"1\"/>"
            }.joined() + "</cols>"
        }
        xml += "<sheetData>"
        for (r, row) in sheet.rows.enumerated() {
            xml += "<row r=\"\(r + 1)\">"
            for (c, value) in row.enumerated() where !value.isEmpty {
                xml += cell(value, ref: SheetRange.name(c + 1) + "\(r + 1)", header: r == 0)
            }
            xml += "</row>"
        }
        return xml + "</sheetData></worksheet>"
    }

    private static func cell(_ value: String, ref: String, header: Bool) -> String {
        let style = header ? " s=\"1\"" : ""
        if !header, value.hasPrefix("="), !SheetValues.isForbidden(value) {
            return "<c r=\"\(ref)\"\(style)><f>\(xml(String(value.dropFirst())))</f></c>"
        }
        if !header, isPlainNumber(value) {
            return "<c r=\"\(ref)\"\(style)><v>\(value)</v></c>"
        }
        return "<c r=\"\(ref)\"\(style) t=\"inlineStr\"><is><t>\(xml(value))</t></is></c>"
    }

    /// "12", "-3.5": a number. "$12k", "007", "1,200": text, as written.
    static func isPlainNumber(_ text: String) -> Bool {
        text.range(of: #"^-?(0|[1-9][0-9]{0,14})(\.[0-9]+)?$"#, options: .regularExpression) != nil
    }

    /// Escaped, and without the control characters XML 1.0 forbids.
    public static func xml(_ text: String) -> String {
        DocumentHTML.escape(String(text.unicodeScalars.filter {
            $0.value >= 0x20 || $0 == "\t" || $0 == "\n" || $0 == "\r"
        }.map(Character.init)))
            .replacingOccurrences(of: "&#39;", with: "&apos;")
    }

    private static func contentTypes(_ count: Int) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Override PartName=\"/xl/workbook.xml\" "
            + "ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
            + "<Override PartName=\"/xl/styles.xml\" "
            + "ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
            + (1...count).map {
                "<Override PartName=\"/xl/worksheets/sheet\($0).xml\" "
                    + "ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            }.joined() + "</Types>"
    }

    private static let rootRels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        + "<Relationship Id=\"rId1\" "
        + "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" "
        + "Target=\"xl/workbook.xml\"/></Relationships>"

    private static func workbook(_ sheets: [Sheet]) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" "
            + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>"
            + sheets.enumerated().map {
                "<sheet name=\"\(xml($0.element.name))\" sheetId=\"\($0.offset + 1)\" r:id=\"rId\($0.offset + 1)\"/>"
            }.joined() + "</sheets></workbook>"
    }

    private static func workbookRels(_ count: Int) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + (1...count).map {
                "<Relationship Id=\"rId\($0)\" "
                    + "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" "
                    + "Target=\"worksheets/sheet\($0).xml\"/>"
            }.joined()
            + "<Relationship Id=\"rId\(count + 1)\" "
            + "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" "
            + "Target=\"styles.xml\"/></Relationships>"
    }

    /// Two cell formats: plain, and the bold header on a light fill.
    private static let styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        + "<fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font>"
        + "<font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>"
        + "<fills count=\"3\"><fill><patternFill patternType=\"none\"/></fill>"
        + "<fill><patternFill patternType=\"gray125\"/></fill>"
        + "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF\(DocumentTheme.surface)\"/></patternFill></fill></fills>"
        + "<borders count=\"1\"><border/></borders>"
        + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        + "<cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
        + "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\"/>"
        + "</cellXfs></styleSheet>"
}
