import Foundation

extension BrowserPolicy {
    private static let valueLimit = 200

    /// Share of the budget the page text keeps when elements and text do not both fit: a page with
    /// hundreds of controls must not push its own words out of the answer.
    private static let textShare = 0.4

    /// The text the model reads: header, numbered elements, then page text,
    /// cut to `maxBytes` of UTF-8 with the truncation note inside the budget.
    package static func render(_ page: BrowserPage, maxBytes: Int, language: AppLanguage = .en) -> String {
        let clean = scrub(page)
        let head = "\(clean.title) \u{2014} \(clean.url)"
        let shown = clean.elements.count
        var lines = clean.elements.map(line)
        if let total = clean.total, total > shown { lines.append(BrowserCopy.elementsShown(shown, of: total, language)) }
        let note = BrowserCopy.truncationNote(language)
        let whole = ([head] + lines + (clean.text.isEmpty ? [] : ["", clean.text])).joined(separator: "\n")
        if whole.utf8.count <= maxBytes { return clean.truncated ? fit(whole, note, maxBytes) : whole }
        let room = maxBytes - note.utf8.count - 1
        guard room > head.utf8.count else { return fit(whole, note, maxBytes) }
        let reserved = min(clean.text.utf8.count, Int(Double(room) * textShare))
        var used = head.utf8.count
        var kept: [String] = []
        for entry in lines {
            let cost = entry.utf8.count + 1
            if used + cost > room - reserved { break }
            used += cost
            kept.append(entry)
        }
        var out = ([head] + kept).joined(separator: "\n")
        // The blank separator and the text's own newline are two bytes of the text's room.
        let textRoom = room - used - 2
        if !clean.text.isEmpty, textRoom > 0 { out += "\n\n" + byteCut(clean.text, textRoom) }
        return out + "\n" + note
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
