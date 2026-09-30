import Foundation

/// Which sampling parameters a model will actually accept.
///
/// Reasoning models do not ignore `temperature` — they answer 400 with
/// `unsupported_value` ("Only the default (1) value is supported"). Inside the
/// provider ladder that reads as one more dead provider, so the user is told
/// there is nothing to talk to when the real problem is one field in the body.
package enum ChatParameters: Sendable {
    /// HACK: matched by model name. The honest test is the provider's own
    /// error body, which this codebase does not read yet — `ChatSSEAttempt`
    /// maps a status code and discards the body. Upgrade trigger: the first
    /// time a model outside these families rejects a parameter, parse the
    /// error and let the provider answer instead of guessing from a string.
    private static let reasoningPrefixes = ["o1", "o3", "o4", "gpt-5", "gpt-oss"]

    package static func acceptsTemperature(_ model: String) -> Bool {
        let name = family(of: model)
        return !reasoningPrefixes.contains { prefix in
            // Prefix, then a boundary: `o3` and `o3-mini` are reasoning models,
            // `mistral-nemo3` is not, and a substring match cannot tell them
            // apart.
            guard name.hasPrefix(prefix) else { return false }
            let rest = name.dropFirst(prefix.count)
            guard let next = rest.first else { return true }
            return next == "-" || next == "." || next.isNumber
        }
    }

    /// Strips the vendor prefix an aggregator adds (`openai/gpt-4o`) so the
    /// family is judged on the model, not on who is reselling it.
    private static func family(of model: String) -> String {
        let name = model.lowercased()
        guard let slash = name.lastIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }
}
