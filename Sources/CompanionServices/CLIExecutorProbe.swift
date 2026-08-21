import CompanionCore
import Foundation

/// Detecta los ejecutores CLI opcionales instalados en la máquina.
/// Catálogo posible: [claude-code, hermes]; sin binarios queda vacío y el
/// proveedor solo ofrece el nativo (ADR 001).
public struct CLIExecutorProbe: Sendable {
    private let locator: CLIBinaryLocator

    public init(locator: CLIBinaryLocator = CLIBinaryLocator()) {
        self.locator = locator
    }

    /// Descriptores de los CLI presentes, en orden estable.
    public func detectAvailable() async -> [ExecutorDescriptor] {
        var detected: [ExecutorDescriptor] = []
        if locator.locate("claude") != nil {
            detected.append(ExecutorDescriptor(
                id: ExecutorID(rawValue: "claude-code"),
                shortName: "claude",
                title: "Claude Code",
                kind: .detectedCLI,
                modelArgs: ["--model", "opus"]
            ))
        }
        if locator.locate("hermes") != nil {
            detected.append(ExecutorDescriptor(
                id: ExecutorID(rawValue: "hermes"),
                shortName: "hermes",
                title: "Hermes",
                kind: .detectedCLI,
                modelArgs: []
            ))
        }
        return detected
    }

    /// Ruta real para lanzar el ejecutor elegido; nil si ya no está.
    public func executablePath(for id: ExecutorID) -> String? {
        switch id.rawValue {
        case "claude-code": return locator.locate("claude")
        case "hermes": return locator.locate("hermes")
        default: return nil
        }
    }
}
