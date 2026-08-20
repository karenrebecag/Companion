import Foundation

/// Native is always present; CLI adapters are detected later (ADR 001).
public struct ExecutorID: RawRepresentable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let native = ExecutorID(rawValue: "native")
}

public struct ExecutorDescriptor: Sendable, Equatable, Identifiable {
    public var id: ExecutorID
    public var shortName: String
    public var title: String
    public var kind: Kind
    public var modelArgs: [String]

    public enum Kind: Sendable, Equatable {
        case native
        case detectedCLI
    }

    public init(
        id: ExecutorID,
        shortName: String,
        title: String,
        kind: Kind,
        modelArgs: [String] = []
    ) {
        self.id = id
        self.shortName = shortName
        self.title = title
        self.kind = kind
        self.modelArgs = modelArgs
    }
}

public enum ExecutorCatalog: Sendable {
    public static let native = ExecutorDescriptor(
        id: .native,
        shortName: "native",
        title: "Nativo",
        kind: .native
    )

    /// Native first; later detections append. Duplicate ids are skipped so
    /// a probe cannot hide or double the built-in executor.
    public static func list(detected: [ExecutorDescriptor]) -> [ExecutorDescriptor] {
        var seen: Set<ExecutorID> = [native.id]
        var result = [native]
        for descriptor in detected where seen.insert(descriptor.id).inserted {
            result.append(descriptor)
        }
        return result
    }
}
