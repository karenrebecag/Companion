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

    /// The whole run when it passes Luhn, or a 15/16 digit card with a 3/4 digit
    /// CVV glued before or after it. Any-window search would mask one in ten
    /// ordinary long numbers by chance, so only those two shapes are tried.
    static func cardWindow(in run: String) -> Range<String.Index>? {
        let digits = run.indices.filter { run[$0].isNumber }
        func span(_ from: Int, _ count: Int) -> Range<String.Index> {
            digits[from]..<run.index(after: digits[from + count - 1])
        }
        if digits.count <= 19, isCardNumber(run) { return span(0, digits.count) }
        for cvv in [3, 4] {
            let length = digits.count - cvv
            guard (15...16).contains(length) else { continue }
            for start in [0, cvv] where isCardNumber(String(run[span(start, length)])) {
                return span(start, length)
            }
        }
        return nil
    }

    /// Long base64 with all three character classes: a path or a word list
    /// does not look like this.
    static func isBase64Blob(_ text: String) -> Bool {
        text.contains(where: \.isUppercase) && text.contains(where: \.isLowercase)
            && text.contains(where: \.isNumber) && !text.contains("//")
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
