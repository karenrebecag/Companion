import Foundation

/// Typed readers over the untyped JSON of a `present` block. Each returns nil
/// for anything it cannot read exactly, so a family parser rejects a field
/// instead of guessing at it.
extension PresentParser {
    static func text(_ dict: [String: Any], _ key: String) -> String? {
        guard let raw = dict[key] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= PresentContract.Limits.maxTextBytes
        else { return nil }
        return trimmed
    }

    /// A field that may be absent. Present but unreadable is still nil: the
    /// caller decides whether a bad optional field sinks the block.
    static func optionalText(_ dict: [String: Any], _ key: String) -> String? {
        text(dict, key)
    }

    static func array(_ dict: [String: Any], _ key: String) -> [Any]? {
        dict[key] as? [Any]
    }

    static func objects(_ dict: [String: Any], _ key: String) -> [[String: Any]]? {
        guard let list = array(dict, key) else { return nil }
        return list.compactMap { $0 as? [String: Any] }
    }

    /// NSNumber boxes booleans too, and `true` must not read as 1. A number the
    /// model wrote as a string ("12", "3.5") is still a number.
    static func number(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let double = Double(trimmed), double.isFinite else { return nil }
            return double
        }
        return nil
    }

    static func numbers(_ value: Any?) -> [Double]? {
        guard let list = value as? [Any] else { return nil }
        var out: [Double] = []
        out.reserveCapacity(list.count)
        for item in list {
            guard let double = number(item) else { return nil }
            out.append(double)
        }
        return out
    }

    /// A cell or a label that the model may have written as a number.
    static func scalarText(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let double = number(value) {
            return PresentCell.number(double).display
        }
        return nil
    }

    /// A numeric string becomes a number only when it reads back the same, so
    /// "007" or an id stays text while "12" sorts as 12.
    static func cell(_ value: Any) -> PresentCell? {
        if value is NSNull { return .text("") }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let double = number(trimmed), PresentCell.number(double).display == trimmed {
                return .number(double)
            }
            return .text(trimmed)
        }
        if let double = number(value) { return .number(double) }
        if let bool = value as? NSNumber, CFGetTypeID(bool) == CFBooleanGetTypeID() {
            return .text(bool.boolValue ? "true" : "false")
        }
        return nil
    }

    static func tone(_ dict: [String: Any], default fallback: PresentTone) -> PresentTone {
        guard let raw = dict["tone"] as? String, let tone = PresentTone(rawValue: raw.lowercased())
        else { return fallback }
        return tone
    }

    /// ISO 8601 only: a date the model wrote as prose stays text and cannot
    /// start a countdown.
    static func isoDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// Only https reaches the UI: a plain http link does not travel and a
    /// javascript: link must never reach a view.
    static func httpsURL(_ text: String?) -> String? {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https",
              url.host != nil
        else { return nil }
        return text
    }

    static func bounded<T>(_ list: [T], max: Int) -> [T] {
        list.count > max ? Array(list.prefix(max)) : list
    }
}
