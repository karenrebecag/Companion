import Foundation

/// The patterns in this app are literals: one that does not compile is a bug
/// to stop on at once, not an error to swallow as "no match".
package enum ConstantPattern {
    package static func compile(
        _ pattern: String, options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("regex constante invalida \(pattern): \(error)")
        }
    }
}
