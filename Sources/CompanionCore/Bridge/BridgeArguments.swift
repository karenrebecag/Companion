import Foundation

/// Audit M6: the constraints the hello declares, checked again where the
/// call lands. The shim refuses the same things first; this is for a client
/// that skips it, so a typo or an oversized value is refused by name instead
/// of being dropped or reaching the runner.
package enum BridgeArguments {
    /// The caller chose the key; it goes back to the model, so not whole.
    static let echoedKeyLimit = 64

    /// Nil when the call fits the spec. Types and required keys stay with
    /// the runner, whose messages already name them. Only top-level strings
    /// are checked: every bridge tool's arguments are flat.
    package static func violation(_ argumentsJSON: String, spec: ToolSpec) -> String? {
        guard let arguments = jsonObject(from: argumentsJSON) else { return nil }
        let declared = Dictionary(spec.properties.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for key in arguments.keys.sorted() {
            guard let property = declared[key] else {
                let shown = key.count > echoedKeyLimit ? key.prefix(echoedKeyLimit) + "…" : key[...]
                return "\(spec.name): unknown argument `\(shown)`"
            }
            guard let value = arguments[key] as? String else { continue }
            if let problem = problem(value, property) { return "\(spec.name): `\(key)` \(problem)" }
        }
        return nil
    }

    private static func problem(_ value: String, _ property: ToolProperty) -> String? {
        if let allowed = property.allowed {
            return allowed.contains(value) ? nil : "must be one of: " + allowed.joined(separator: ", ")
        }
        let bytes = value.utf8.count
        let fits = !value.utf8.contains(0)
            && property.minLength.map { value.count >= $0 } ?? true
            && property.maxBytes.map { bytes <= $0 } ?? true
        guard !fits else { return nil }
        switch (property.minLength, property.maxBytes) {
        case let (min?, max?): return "must contain \(min)-\(max) UTF-8 bytes and no NUL"
        case let (nil, max?): return "must contain at most \(max) UTF-8 bytes and no NUL"
        case let (min?, nil): return "must contain at least \(min) characters and no NUL"
        case (nil, nil): return "must contain no NUL"
        }
    }
}
