import CompanionCore
import Foundation

/// Detecta los ejecutores CLI opcionales instalados en la máquina y despliega
/// sus variantes: los tiers que el CLI de claude documenta como alias, y los
/// proveedores que hermes ya tiene configurados en su propio cache. Sin
/// binarios el catálogo queda vacío y el proveedor solo ofrece el nativo
/// (ADR 001) — nada se asume, todo se detecta.
public struct CLIExecutorProbe: Sendable {
    private let locator: CLIBinaryLocator
    private let hermesProviders: @Sendable () -> [String]

    public init(
        locator: CLIBinaryLocator = CLIBinaryLocator(),
        hermesProviders: (@Sendable () -> [String])? = nil
    ) {
        self.locator = locator
        self.hermesProviders = hermesProviders ?? { HermesProviderScan.providers() }
    }

    /// Un tier por alias documentado del CLI. Sonnet encabeza: es el
    /// especialista de trabajo por defecto (herramientas completas sin el
    /// costo de Opus para un encargo típico — la misma decisión del
    /// prototipo, AgentChoice.claudeWorker).
    static let claudeTiers: [(suffix: String, title: String, alias: String)] = [
        ("", "Claude · Sonnet 5", "sonnet"),
        (":fable", "Claude · Fable 5", "fable"),
        (":opus", "Claude · Opus 5", "opus"),
        (":haiku", "Claude · Haiku 4.5", "haiku"),
    ]

    /// Descriptores de los CLI presentes, en orden estable.
    public func detectAvailable() async -> [ExecutorDescriptor] {
        var detected: [ExecutorDescriptor] = []
        if locator.locate("claude") != nil {
            for tier in Self.claudeTiers {
                detected.append(ExecutorDescriptor(
                    id: ExecutorID(rawValue: "claude-code" + tier.suffix),
                    shortName: "claude",
                    title: tier.title,
                    kind: .detectedCLI,
                    modelArgs: ["--model", tier.alias]
                ))
            }
        }
        if locator.locate("hermes") != nil {
            detected.append(ExecutorDescriptor(
                id: ExecutorID(rawValue: "hermes"),
                shortName: "hermes",
                title: "Hermes · cadena por defecto",
                kind: .detectedCLI,
                modelArgs: []
            ))
            for provider in hermesProviders() {
                detected.append(ExecutorDescriptor(
                    id: ExecutorID(rawValue: "hermes:" + provider),
                    shortName: "hermes",
                    title: "Hermes · " + Self.prettyProvider(provider),
                    kind: .detectedCLI,
                    modelArgs: ["--provider", provider]
                ))
            }
        }
        return detected
    }

    /// Ruta real para lanzar el ejecutor elegido; nil si ya no está.
    public func executablePath(for id: ExecutorID) -> String? {
        if id.rawValue.hasPrefix("claude-code") { return locator.locate("claude") }
        if id.rawValue.hasPrefix("hermes") { return locator.locate("hermes") }
        return nil
    }

    /// Nombres de pantalla para ids conocidos; el resto capitalizado tal cual
    /// viene — el id del cache es la verdad, el título solo lo viste.
    static func prettyProvider(_ id: String) -> String {
        switch id {
        case "openrouter": return "OpenRouter"
        case "copilot": return "Copilot"
        case "xai-oauth": return "Grok (xAI)"
        case "anthropic": return "Anthropic"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}
