import Foundation

/// The one JSON reader the judge uses, for the model's verdicts, for the
/// action summary and for the version digest. Three readers that disagree
/// would let the judge see one set of arguments and the version another.
///
/// Strict on purpose: `JSONDecoder` and `JSONSerialization` both keep the last
/// of two equal keys, so `{"covered":false,...,"covered":true}` would read as
/// covered. A repeated key, a number a Double would round, or a document nested
/// past `maxDepth` is a parse failure here, and a failure is never covered.
enum JSONValue: Equatable {
    case null
    case bool(Bool)
    /// The lexeme as written plus its value, so a version keeps every digit.
    case number(String, Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    static let maxDepth = 32

    static func parse(_ data: Data) -> JSONValue? {
        var reader = JSONReader(bytes: Array(data))
        return reader.document()
    }
}

// MARK: - Canonical bytes

extension JSONValue {
    /// Injective: strings and numbers carry their length and containers close,
    /// so two different values can never write the same bytes. Object members
    /// are ordered by their UTF-8 bytes, which makes key order irrelevant.
    func canonicalBytes() -> [UInt8] {
        var out: [UInt8] = []
        write(to: &out)
        return out
    }

    private func write(to out: inout [UInt8]) {
        switch self {
        case .null: out.append(UInt8(ascii: "n"))
        case .bool(let flag): out.append(UInt8(ascii: flag ? "t" : "f"))
        case .number(let lexeme, _): Self.writeCounted("#", lexeme, to: &out)
        case .string(let text): Self.writeCounted("s", text, to: &out)
        case .array(let items):
            out.append(UInt8(ascii: "["))
            for item in items { item.write(to: &out) }
            out.append(UInt8(ascii: "]"))
        case .object(let members):
            out.append(UInt8(ascii: "{"))
            for key in members.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
                Self.writeCounted("s", key, to: &out)
                members[key]?.write(to: &out)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    private static func writeCounted(_ tag: Character, _ text: String, to out: inout [UInt8]) {
        out.append(contentsOf: Array(String(tag).utf8))
        out.append(contentsOf: Array("\(text.utf8.count):".utf8))
        out.append(contentsOf: Array(text.utf8))
    }
}

// MARK: - Numbers

extension JSONValue {
    /// True when the Double is the number that was written, not a rounding of
    /// it. Compared as decimals (sign, significant digits, exponent) against
    /// the Double's shortest form, so `1E5` and `100000` agree and
    /// `9007199254740993` does not.
    static func roundTrips(_ lexeme: String, _ value: Double) -> Bool {
        guard let written = Decimal10(parsing: lexeme), let kept = Decimal10(parsing: "\(value)") else {
            return false
        }
        return written == kept
    }

    private struct Decimal10: Equatable {
        /// A Double's shortest form never writes an exponent past ±324, so a
        /// larger one cannot round-trip. Refusing it here also keeps the scale
        /// arithmetic below far from `Int` overflow: `1.0e-9223372036854775808`
        /// reads as a finite 0.0, and `-1 + Int.min` would trap the app.
        static let maxExponent = 400

        let negative: Bool
        let digits: [UInt8]
        let exponent: Int

        init?(parsing text: String) {
            var rest = Substring(text)
            negative = rest.first == "-"
            if negative { rest = rest.dropFirst() }
            let parts = rest.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "e" || $0 == "E" })
            guard let mantissa = parts.first, parts.count <= 2 else { return nil }
            let point = mantissa.split(separator: ".", omittingEmptySubsequences: false)
            var significant = Array((point[0] + (point.count > 1 ? point[1] : "")).utf8).drop { $0 == 0x30 }
            var scale = -(point.count > 1 ? point[1].utf8.count : 0)
            if parts.count == 2 {
                guard let written = Int(parts[1].hasPrefix("+") ? parts[1].dropFirst() : parts[1]),
                      // Not `abs(written)`: `abs(Int.min)` traps too.
                      (-Self.maxExponent ... Self.maxExponent).contains(written)
                else { return nil }
                scale += written
            }
            while significant.last == 0x30 {
                significant.removeLast()
                scale += 1
            }
            digits = Array(significant)
            exponent = digits.isEmpty ? 0 : scale
        }
    }
}

// MARK: - Reader

private struct JSONReader {
    let bytes: [UInt8]
    var position = 0

    private var peek: UInt8? { position < bytes.count ? bytes[position] : nil }

    mutating func document() -> JSONValue? {
        skipSpace()
        guard let parsed = value(depth: 0) else { return nil }
        skipSpace()
        return position == bytes.count ? parsed : nil
    }

    private mutating func skipSpace() {
        while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { position += 1 }
    }

    private mutating func value(depth: Int) -> JSONValue? {
        guard let byte = peek else { return nil }
        switch byte {
        case UInt8(ascii: "{"): return object(depth: depth)
        case UInt8(ascii: "["): return array(depth: depth)
        case UInt8(ascii: "\""): return string().map(JSONValue.string)
        case UInt8(ascii: "t"): return literal("true", .bool(true))
        case UInt8(ascii: "f"): return literal("false", .bool(false))
        case UInt8(ascii: "n"): return literal("null", .null)
        default: return number()
        }
    }

    private mutating func literal(_ word: String, _ result: JSONValue) -> JSONValue? {
        let expected = Array(word.utf8)
        guard position + expected.count <= bytes.count,
              Array(bytes[position ..< position + expected.count]) == expected
        else { return nil }
        position += expected.count
        return result
    }

    /// `depth` counts the containers already open, so the container being read
    /// is level `depth + 1`: level 32 is the last one allowed.
    private mutating func object(depth: Int) -> JSONValue? {
        guard depth < JSONValue.maxDepth else { return nil }
        position += 1
        skipSpace()
        if peek == UInt8(ascii: "}") {
            position += 1
            return .object([:])
        }
        var members: [String: JSONValue] = [:]
        while true {
            skipSpace()
            guard peek == UInt8(ascii: "\""), let key = string() else { return nil }
            skipSpace()
            guard peek == UInt8(ascii: ":") else { return nil }
            position += 1
            skipSpace()
            guard let member = value(depth: depth + 1) else { return nil }
            guard members.updateValue(member, forKey: key) == nil else { return nil }
            skipSpace()
            switch peek {
            case UInt8(ascii: ","): position += 1
            case UInt8(ascii: "}"):
                position += 1
                return .object(members)
            default: return nil
            }
        }
    }

    private mutating func array(depth: Int) -> JSONValue? {
        guard depth < JSONValue.maxDepth else { return nil }
        position += 1
        skipSpace()
        if peek == UInt8(ascii: "]") {
            position += 1
            return .array([])
        }
        var items: [JSONValue] = []
        while true {
            skipSpace()
            guard let item = value(depth: depth + 1) else { return nil }
            items.append(item)
            skipSpace()
            switch peek {
            case UInt8(ascii: ","): position += 1
            case UInt8(ascii: "]"):
                position += 1
                return .array(items)
            default: return nil
            }
        }
    }

    private mutating func number() -> JSONValue? {
        let start = position
        if peek == UInt8(ascii: "-") { position += 1 }
        guard let first = peek else { return nil }
        if first == UInt8(ascii: "0") {
            position += 1
        } else if isDigit(first) {
            skipDigits()
        } else {
            return nil
        }
        if peek == UInt8(ascii: ".") {
            position += 1
            guard skipDigits() > 0 else { return nil }
        }
        if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
            position += 1
            if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { position += 1 }
            guard skipDigits() > 0 else { return nil }
        }
        let lexeme = String(decoding: bytes[start ..< position], as: UTF8.self)
        guard let value = Double(lexeme), value.isFinite else { return nil }
        return .number(lexeme, value)
    }

    private func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    @discardableResult
    private mutating func skipDigits() -> Int {
        var count = 0
        while let byte = peek, isDigit(byte) {
            position += 1
            count += 1
        }
        return count
    }

    // MARK: Strings

    private mutating func string() -> String? {
        position += 1
        var out: [UInt8] = []
        while let byte = peek {
            position += 1
            switch byte {
            case UInt8(ascii: "\""):
                // Not `String(bytes:encoding:)`: it drops a leading U+FEFF, so
                // `<BOM>bob` and `bob` would read as the same key or value.
                return String(validating: out, as: UTF8.self)
            case UInt8(ascii: "\\"):
                guard let scalar = escape() else { return nil }
                out.append(contentsOf: Array(String(scalar).utf8))
            case 0x00 ..< 0x20:
                return nil
            default:
                out.append(byte)
            }
        }
        return nil
    }

    private mutating func escape() -> Unicode.Scalar? {
        guard let byte = peek else { return nil }
        position += 1
        switch byte {
        case UInt8(ascii: "\""): return "\""
        case UInt8(ascii: "\\"): return "\\"
        case UInt8(ascii: "/"): return "/"
        case UInt8(ascii: "b"): return "\u{08}"
        case UInt8(ascii: "f"): return "\u{0C}"
        case UInt8(ascii: "n"): return "\n"
        case UInt8(ascii: "r"): return "\r"
        case UInt8(ascii: "t"): return "\t"
        case UInt8(ascii: "u"): return unicodeEscape()
        default: return nil
        }
    }

    /// A lone surrogate is not a scalar; it fails rather than becoming U+FFFD,
    /// because a replaced character would make two different texts equal.
    private mutating func unicodeEscape() -> Unicode.Scalar? {
        guard let high = hex4() else { return nil }
        switch high {
        case 0xD800 ... 0xDBFF:
            guard peek == UInt8(ascii: "\\"), position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "u") else {
                return nil
            }
            position += 2
            guard let low = hex4(), (0xDC00 ... 0xDFFF).contains(low) else { return nil }
            return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
        case 0xDC00 ... 0xDFFF:
            return nil
        default:
            return Unicode.Scalar(high)
        }
    }

    private mutating func hex4() -> UInt32? {
        guard position + 4 <= bytes.count else { return nil }
        var result: UInt32 = 0
        for byte in bytes[position ..< position + 4] {
            guard let digit = Character(Unicode.Scalar(byte)).hexDigitValue else { return nil }
            result = result * 16 + UInt32(digit)
        }
        position += 4
        return result
    }
}
