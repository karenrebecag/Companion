import Foundation

/// How a validated `present` call travels inside a reply. The fence is the
/// storage form, not something the model writes: its body is the call's own
/// arguments, so a saved chat re-renders through the same parser and resolver
/// it was first drawn with, and nothing else has to know about present.
package enum PresentFence {
    package static let language = "companion:present"

    /// Nil when the arguments are not a call with blocks, or when they exceed
    /// the size the parser accepts. The body is re-serialized with sorted keys
    /// so the same call always produces the same saved text.
    package static func body(argumentsJSON: String) -> String? {
        guard argumentsJSON.utf8.count <= PresentContract.Limits.maxArgumentBytes,
              let data = argumentsJSON.data(using: .utf8)
        else { return nil }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
        guard let dict = object as? [String: Any], dict["blocks"] is [Any] else { return nil }
        do {
            let out = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
            return String(decoding: out, as: UTF8.self)
        } catch {
            return nil
        }
    }

    /// Renders a saved body. A body that no longer parses renders nothing; the
    /// caller shows it as code instead of dropping it.
    package static func renders(body: String, now: Date = Date()) -> [PresentRender]? {
        guard let outcome = outcome(body: body), !outcome.blocks.isEmpty else { return nil }
        return BlockResolver.resolveAll(outcome.blocks, now: now)
    }

    package static func outcome(body: String) -> PresentOutcome? {
        guard body.utf8.count <= PresentContract.Limits.maxArgumentBytes,
              let data = body.data(using: .utf8)
        else { return nil }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
        guard let dict = object as? [String: Any] else { return nil }
        return PresentParser.parse(arguments: dict)
    }

    /// The reply as the reader sees it: each present fence becomes the words of
    /// its blocks. Language detection reads this, so the JSON the model wrote
    /// (English keys, a language of its own) never decides the reply's language.
    package static func paintedWords(of reply: String) -> String {
        var out: [String] = []
        var open: [String]?
        for line in reply.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let body = open {
                if trimmed.hasPrefix("```") {
                    out += words(ofBody: body.joined(separator: "\n"))
                    open = nil
                } else {
                    open = body + [line]
                }
            } else if isOpener(trimmed) {
                open = []
            } else {
                out.append(line)
            }
        }
        // A fence the text ends inside is still arriving: its JSON paints nothing.
        return out.joined(separator: "\n")
    }

    private static func isOpener(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("```") else { return false }
        return trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces) == language
    }

    private static func words(ofBody body: String) -> [String] {
        guard let outcome = outcome(body: body) else { return [] }
        return outcome.blocks.flatMap(PresentReadable.lines)
    }
}
