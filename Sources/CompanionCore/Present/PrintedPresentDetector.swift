import Foundation

/// Finds a `present` call the model printed into its reply as text. Some
/// models write the JSON out instead of calling the tool; the user should
/// still see cards, and the next turn should say what happened.
package enum PrintedPresentDetector {
    package struct Hit: Sendable, Equatable {
        /// The reply with the JSON (and any empty fence around it) removed.
        package var prose: String
        package var outcome: PresentOutcome
        /// The call's own JSON, so it can be stored like a real call.
        package var json: String

        package init(prose: String, outcome: PresentOutcome, json: String) {
            self.prose = prose
            self.outcome = outcome
            self.json = json
        }
    }

    /// Said to the model on its next turn, once, when a reply printed the
    /// JSON. It names the fix; the cards already came out right.
    package static let correction = "Your last reply printed the present JSON as text. "
        + "The client rendered it as cards, but the next time call the present tool "
        + "instead of writing its JSON into the reply."

    /// Only an object with a `blocks` array whose items name a known family
    /// counts, so an ordinary JSON example in a code fence is left alone.
    ///
    /// Candidates are the braces opened just before a `"blocks"` key: the
    /// call's own object encloses that key, so a short backward walk finds it
    /// without trying every brace in a long reply.
    package static func detect(in text: String) -> Hit? {
        guard text.utf8.count <= PresentContract.Limits.maxArgumentBytes,
              text.contains("\"blocks\"")
        else { return nil }
        let chars = Array(text)
        for key in blocksKeys(in: chars) {
            for start in openBraces(before: key, in: chars, limit: maxCandidatesPerKey) {
                guard let end = closingBrace(in: chars, from: start), end > key,
                      let hit = hit(in: chars, from: start, to: end)
                else { continue }
                return hit
            }
        }
        return nil
    }

    private static let maxCandidatesPerKey = 8
    private static let blocksKey = Array("\"blocks\"")

    private static func blocksKeys(in chars: [Character]) -> [Int] {
        guard chars.count >= blocksKey.count else { return [] }
        var keys: [Int] = []
        for index in 0...(chars.count - blocksKey.count)
        where chars[index] == "\"" && Array(chars[index..<(index + blocksKey.count)]) == blocksKey {
            keys.append(index)
        }
        return keys
    }

    private static func openBraces(before key: Int, in chars: [Character], limit: Int) -> [Int] {
        var found: [Int] = []
        var index = key - 1
        while index >= 0, found.count < limit {
            if chars[index] == "{" { found.append(index) }
            index -= 1
        }
        return found
    }

    private static func hit(in chars: [Character], from start: Int, to end: Int) -> Hit? {
        let json = String(chars[start...end])
        guard let object = jsonObject(json), looksLikePresent(object)
        else { return nil }
        let outcome = PresentParser.parse(arguments: object)
        let before = String(chars[..<start])
        let after = String(chars[(end + 1)...])
        return Hit(prose: joinedProse(before, after), outcome: outcome, json: json)
    }

    /// A candidate that is not JSON is the normal case while scanning a reply,
    /// so it is a miss, not an error to report.
    private static func jsonObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func looksLikePresent(_ object: [String: Any]) -> Bool {
        guard let blocks = object["blocks"] as? [Any], !blocks.isEmpty else { return false }
        return blocks.contains { item in
            guard let dict = item as? [String: Any], let type = dict["type"] as? String else { return false }
            let key = type.lowercased()
            return PresentParser.familiesByName[key] != nil
        }
    }

    /// The index of the brace that closes `start`, skipping braces inside
    /// strings. Nil when the text ends first: a reply cut mid-JSON is not a call.
    private static func closingBrace(in chars: [Character], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < chars.count {
            let char = chars[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "\"" {
                inString = true
            } else if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    /// The fence the JSON sat in is left empty once the JSON is gone; it is
    /// removed rather than painted as an empty code block.
    private static func joinedProse(_ before: String, _ after: String) -> String {
        let joined = before + after
        let emptyFence = #"```[a-zA-Z]*\s*```"#
        return joined.replacingOccurrences(of: emptyFence, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
