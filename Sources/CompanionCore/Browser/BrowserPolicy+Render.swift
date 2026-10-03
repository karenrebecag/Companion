import Foundation

extension BrowserPolicy {
    private static let valueLimit = 200

    /// The text the model reads: header, numbered elements, then page text,
    /// cut to `maxBytes` of UTF-8 with the truncation note inside the budget.
    package static func render(_ page: BrowserPage, maxBytes: Int, language: AppLanguage = .en) -> String {
        let clean = scrub(page)
        var lines = ["\(clean.title) — \(clean.url)"]
        lines += clean.elements.map(line)
        if !clean.text.isEmpty { lines += ["", clean.text] }
        let whole = lines.joined(separator: "\n")
        let note = BrowserCopy.truncationNote(language)
        if whole.utf8.count <= maxBytes { return clean.truncated ? fit(whole, note, maxBytes) : whole }
        return fit(whole, note, maxBytes)
    }

    private static func line(_ element: BrowserElement) -> String {
        var text = "[\(element.id)] \(element.role) \"\(escaped(element.label))\""
        if !element.states.isEmpty { text += " (\(element.states.joined(separator: ", ")))" }
        if let origin = element.frameOrigin {
            text += " (frame \(element.frame), origin \(escaped(origin)))"
        } else if element.frame > 0 {
            text += " (frame \(element.frame))"
        }
        if let value = element.value, !value.isEmpty { text += " = \"\(escaped(String(value.prefix(valueLimit))))\"" }
        if !element.context.isEmpty { text += " — \(escaped(element.context))" }
        return text
    }

    /// Element text is page-controlled: a newline or quote in it could forge a
    /// second element line, so it is escaped to keep one element per line.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Cuts on a character boundary so the result stays valid UTF-8, then
    /// appends the note; a budget smaller than the note keeps the note cut.
    private static func fit(_ body: String, _ note: String, _ maxBytes: Int) -> String {
        let suffix = "\n" + note
        let room = maxBytes - suffix.utf8.count
        guard room > 0 else { return byteCut(suffix, maxBytes) }
        if body.utf8.count <= room { return body + suffix }
        return byteCut(body, room) + suffix
    }

    private static func byteCut(_ text: String, _ limit: Int) -> String {
        var used = 0
        var out = ""
        for character in text {
            let size = String(character).utf8.count
            if used + size > limit { break }
            used += size
            out.append(character)
        }
        return out
    }
}
