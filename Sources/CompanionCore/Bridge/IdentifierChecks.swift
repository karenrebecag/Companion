import Foundation

/// Checksums and formats that tell a real identifier from a number that only
/// looks like one, so redaction does not blank every long digit run.
enum IdentifierChecks {
    static func isCardNumber(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            let doubled = offset % 2 == 1 ? digit * 2 : digit
            sum += doubled > 9 ? doubled - 9 : doubled
        }
        return sum % 10 == 0
    }

    static func isCLABE(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard digits.count == 18 else { return false }
        let weights = [3, 7, 1]
        let sum = digits.prefix(17).enumerated().reduce(0) { $0 + ($1.element * weights[$1.offset % 3]) % 10 }
        return (10 - sum % 10) % 10 == digits[17]
    }

    /// Four letters, a valid birth date, sex, state, consonants, check digits.
    static func isCURP(_ text: String) -> Bool {
        let chars = Array(text)
        guard chars.count == 18 else { return false }
        return validDate(String(chars[4..<10]))
            && Self.states.contains(String(chars[11..<13]))
    }

    /// Persona moral (3 letters) or fisica (4 letters) plus a valid date.
    static func isRFC(_ text: String) -> Bool {
        let chars = Array(text)
        guard chars.count == 12 || chars.count == 13 else { return false }
        let lettersEnd = chars.count - 9
        return validDate(String(chars[lettersEnd..<(lettersEnd + 6)]))
    }

    private static func validDate(_ yymmdd: String) -> Bool {
        let digits = yymmdd.compactMap(\.wholeNumberValue)
        guard digits.count == 6 else { return false }
        let month = digits[2] * 10 + digits[3]
        let day = digits[4] * 10 + digits[5]
        return (1...12).contains(month) && (1...31).contains(day)
    }

    private static let states: Set<String> = [
        "AS", "BC", "BS", "CC", "CL", "CM", "CS", "CH", "DF", "DG", "GT", "GR", "HG", "JC", "MC", "MN",
        "MS", "NT", "NL", "OC", "PL", "QT", "QR", "SP", "SL", "SR", "TC", "TS", "TL", "VZ", "YN", "ZS", "NE",
    ]
}
