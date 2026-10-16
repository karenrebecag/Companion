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
        let outcome = PresentParser.parse(arguments: dict)
        guard !outcome.blocks.isEmpty else { return nil }
        return BlockResolver.resolveAll(outcome.blocks, now: now)
    }
}
