import Foundation

/// The wire contract of the `present` tool: one description per family, the
/// bounds the parser enforces, and the JSON schema the provider receives.
///
/// The schema is one object for all families, not one per family. A per-family
/// `oneOf` is the type-safe shape, but it costs several times the tokens on
/// every turn, and the parser already rejects what the schema would reject.
/// The shape lives in the description, one line per family.
package enum PresentContract {
    package enum Limits {
        package static let maxBlocks = 24
        package static let maxRows = 200
        package static let maxColumns = 12
        package static let maxSeriesPoints = 2_000
        package static let maxSeries = 8
        package static let maxParts = 40
        package static let maxItems = 60
        package static let maxTextBytes = 16_000
        /// Past this a single `present` body is refused before it is parsed.
        package static let maxArgumentBytes = 512 * 1024
        /// A sparkline past this is a chart's job; the tile is too small for it.
        package static let maxTrend = 24
        /// Deeper than this, the file tree stops being readable as a tree.
        package static let maxFileDepth = 6
    }

    package static let presentName = "present"
    package static let findBlockName = "find_block"

    /// The schema text the model reads. Built from PresentFamily so the names,
    /// shapes and rules cannot drift apart.
    package static var presentDescription: String {
        let families = PresentFamily.allCases.map { family in
            "\(family.rawValue) {\(family.shape)}: use for \(family.whenToUse); not for \(family.whenNotToUse)."
        }
        return ([
            "Show the reply as typed blocks instead of markdown. One present call carries the whole structured part of a reply, in order; plain sentences can be paragraph blocks.",
            "Pick the family that names what the content is. The client picks the component, so never describe a chart or a table in text.",
            "Data must be what you looked up or were given. Never invent numbers, coordinates or links: figures that change (prices, populations, rates) need a search this turn before you present them.",
            "Do not print this JSON as text in your reply: it is rendered for the user, not shown as code.",
            "Families:",
        ] + families).joined(separator: "\n")
    }

    /// The schema the parser enforces: a non-empty `blocks` array whose items
    /// carry a `type` from the family list. The fields of each family are
    /// taught in the description and checked by the parser, not here.
    package static var presentParameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "blocks": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": Limits.maxBlocks,
                    "items": [
                        "type": "object",
                        "properties": [
                            "type": [
                                "type": "string",
                                "enum": PresentFamily.allCases.map(\.rawValue),
                            ],
                        ],
                        "required": ["type"],
                        "additionalProperties": true,
                    ],
                ],
            ],
            "required": ["blocks"],
        ]
    }

    package static var presentSpec: ToolSpec {
        ToolSpec(
            name: presentName,
            description: presentDescription,
            properties: [],
            required: ["blocks"],
            rawParametersJSON: jsonString(presentParameters))
    }

    /// The long tail: components with no family of their own. Offered only
    /// when no family fits, so the common path never sees this tool.
    package static var findBlockSpec: ToolSpec {
        ToolSpec(
            name: findBlockName,
            description: "Look up a visual block that no present family covers (JSON tree, countdown, heatmap, ridgeline, market terminal, slope, waffle). Returns its id, when to use it and the data it takes. Then emit that block through present only if its shape fits your data.",
            properties: [
                ToolProperty(name: "query", type: "string",
                             description: "what the content is, a few words",
                             minLength: 1, maxBytes: 200),
            ],
            required: ["query"])
    }

    /// The literal schema always serializes; failing here is a programming
    /// error in this file, not a runtime condition to recover from.
    private static func jsonString(_ object: [String: Any]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else {
                preconditionFailure("present schema is not UTF-8")
            }
            return text
        } catch {
            preconditionFailure("present schema does not serialize: \(error)")
        }
    }
}
