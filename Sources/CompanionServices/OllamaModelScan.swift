import CompanionCore
import Foundation

/// What a scan found. Four states, not two: "the daemon is silent" and "the
/// daemon is not installed" need different copy, and telling someone to
/// install what they already have is the kind of lie that loses trust.
public struct OllamaScanResult: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// Daemon answered and a usable chat model was chosen.
        case ready(InstalledModel)
        /// Daemon answered, but nothing installed can hold a conversation.
        case noModel
        /// The binary is on this Mac, but nothing is listening.
        case notRunning
        /// No binary, no daemon.
        case absent
    }

    public var state: State
    public var installed: [InstalledModel]

    public init(state: State, installed: [InstalledModel]) {
        self.state = state
        self.installed = installed
    }
}

/// Read-only detection of the models Ollama already has (ADR 004: one adapter,
/// read-only, and the product behaves identically when Ollama is not there).
/// Never spawns a process — this is HTTP to a daemon the user chose to run.
public struct OllamaModelScan: Sendable {
    /// Paths a Homebrew or a .pkg install leaves the binary in. Probing the
    /// filesystem for someone else's binary is the example ADR 004 names as
    /// allowed; reading their config would not be.
    public static let binaryPaths = [
        "/usr/local/bin/ollama",
        "/opt/homebrew/bin/ollama",
        "/Applications/Ollama.app",
    ]

    private let transport: any ChatTransport
    private let baseURL: URL
    private let timeout: TimeInterval
    private let binaryPresent: @Sendable () -> Bool

    public init(
        transport: any ChatTransport,
        baseURL: URL = URL(string: "http://localhost:11434")!,
        timeout: TimeInterval = 1,
        binaryPresent: (@Sendable () -> Bool)? = nil
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.timeout = timeout
        self.binaryPresent = binaryPresent ?? {
            Self.binaryPaths.contains { FileManager.default.fileExists(atPath: $0) }
        }
    }

    /// Bool-shaped like `LiveCapabilityProbe`: a daemon that is down is "not
    /// here", not an error that breaks the launch.
    public func scan(tier: RAMTier, preferred: String?) async -> OllamaScanResult {
        guard let url = URL(string: baseURL.absoluteString + "/api/tags"),
              EndpointPolicy.isAcceptable(url)
        else {
            // A non-local base must never become the door through which a
            // remote host in the clear gets scanned.
            return OllamaScanResult(state: .absent, installed: [])
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"

        let installed: [InstalledModel]
        do {
            let (data, response) = try await transport.data(for: request)
            guard response.statusCode == 200 else { return silent() }
            installed = try Self.decode(data)
        } catch {
            return silent()
        }

        guard let chosen = LocalModelChoice.choose(
            from: installed, tier: tier, preferred: preferred)
        else {
            return OllamaScanResult(state: .noModel, installed: installed)
        }
        return OllamaScanResult(state: .ready(chosen), installed: installed)
    }

    private func silent() -> OllamaScanResult {
        OllamaScanResult(
            state: binaryPresent() ? .notRunning : .absent, installed: [])
    }

    private struct TagsPayload: Decodable {
        struct Entry: Decodable {
            let name: String
            let size: UInt64
        }
        let models: [Entry]
    }

    static func decode(_ data: Data) throws -> [InstalledModel] {
        let payload = try JSONDecoder().decode(TagsPayload.self, from: data)
        return payload.models.map {
            InstalledModel(name: $0.name, sizeBytes: $0.size)
        }
    }
}

/// Holds the last scan so the hot path never waits on a daemon. Refreshed at
/// launch and on demand — never per request: a scan inside the request would
/// make time-to-first-token depend on someone else's process.
public final class LocalCatalog: @unchecked Sendable {
    private let scan: OllamaModelScan
    private let base: [ProviderDescriptor]
    private let tier: RAMTier
    private let lock = NSLock()
    private var resolved: OllamaScanResult?

    public init(
        scan: OllamaModelScan,
        base: [ProviderDescriptor] = ProviderDescriptor.catalog,
        tier: RAMTier = RAMTier.forBytes(ProcessInfo.processInfo.physicalMemory)
    ) {
        self.scan = scan
        self.base = base
        self.tier = tier
    }

    public var lastResult: OllamaScanResult? {
        lock.lock()
        defer { lock.unlock() }
        return resolved
    }

    @discardableResult
    public func refresh(preferred: String? = nil) async -> OllamaScanResult {
        let result = await scan.scan(tier: tier, preferred: preferred)
        store(result)
        return result
    }

    /// Synchronous on purpose: Swift 6 forbids taking a lock across a suspension
    /// point, so the await happens above and only the write is guarded.
    private func store(_ result: OllamaScanResult) {
        lock.lock()
        defer { lock.unlock() }
        resolved = result
    }

    /// The catalog the router actually walks. Ollama appears ONLY with a tag
    /// that is installed: a descriptor pointing at a model the daemon does not
    /// have passes the health probe and then dies on the POST, which is the
    /// defect this whole piece exists to remove.
    public func effective() -> [ProviderDescriptor] {
        let state = lastResult?.state
        return base.compactMap { provider in
            guard provider.id == ProviderDescriptor.ollama.id else {
                return provider
            }
            guard case .ready(let model) = state else { return nil }
            return provider.withModel(model.name)
        }
    }
}

extension LocalCatalog: StartupProbing {
    /// Apple Foundation Models is not a path yet (Wave 9b-2 decides whether a
    /// 4096-token window can hold a conversation); until then the only local
    /// path is a daemon with a model it actually has.
    public func probe(preferred: String?) async -> [LocalPath] {
        let result = await refresh(preferred: preferred)
        guard case .ready(let model) = result.state else { return [] }
        return [.ollama(model: model.name)]
    }
}
