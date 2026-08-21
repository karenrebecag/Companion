import CompanionCore
import Foundation

public final class ChatProviderClient: ChatProvider, Sendable {
    private let secrets: any SecretStore
    private let probe: any CapabilityProbe
    private let transport: any ChatTransport
    private let settings: ChatSettings
    private let ownerFirstName: String
    private let catalog: [ProviderDescriptor]

    public init(
        secrets: any SecretStore,
        probe: any CapabilityProbe,
        transport: any ChatTransport,
        settings: ChatSettings = .default,
        ownerFirstName: String = "",
        catalog: [ProviderDescriptor] = ProviderDescriptor.catalog
    ) {
        self.secrets = secrets
        self.probe = probe
        self.transport = transport
        self.settings = settings
        self.ownerFirstName = ownerFirstName
        self.catalog = catalog
    }

    public func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.route(
                    history: history, tools: tools, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func verify(_ key: String, provider: ProviderDescriptor) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChatError.invalidKey }
        guard let url = URL(string: provider.baseURL.absoluteString + "/models")
        else { throw ChatError.unreachable }
        // Validate endpoint URL against security policy.
        guard EndpointPolicy.isAcceptable(url) else { throw ChatError.unreachable }

        var request = URLRequest(
            url: url, timeoutInterval: settings.inactivityTimeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")

        let response: HTTPURLResponse
        do {
            (_, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ChatError.timeout
        } catch {
            throw ChatError.unreachable
        }
        if response.statusCode == 200 { return }
        throw ChatSSEAttempt.mapStatus(response.statusCode)
    }

    private func route(
        history: [Turn],
        tools: [ToolSpec],
        continuation: AsyncThrowingStream<ChatDelta, Error>.Continuation
    ) async {
        let providers = ProviderDescriptor.route(
            preferred: settings.preferredProviderName, catalog: catalog)
        do {
            var lastError: ChatError?
            var attempted = false
            for provider in providers {
                try Task.checkCancellation()
                if provider.secretKey != nil, storedKey(for: provider) == nil {
                    continue
                }
                if !(await probe.isAvailable(provider)) { continue }
                attempted = true
                let outcome = await ChatSSEAttempt.run(
                    provider: provider,
                    key: storedKey(for: provider),
                    history: history,
                    tools: tools,
                    settings: settings,
                    ownerFirstName: ownerFirstName,
                    transport: transport,
                    yield: { continuation.yield($0) })
                switch outcome {
                case .cancelled:
                    continuation.finish(throwing: CancellationError())
                    return
                case .failed(let error):
                    lastError = error
                    continue
                case .reply, .spokePartial, .handoff:
                    continuation.finish()
                    return
                }
            }
            continuation.finish(
                throwing: attempted ? (lastError ?? .noProvider) : .noProvider)
        } catch is CancellationError {
            continuation.finish(throwing: CancellationError())
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func storedKey(for provider: ProviderDescriptor) -> String? {
        guard let name = provider.secretKey else { return nil }
        let value: String?
        do {
            value = try secrets.read(name)
        } catch {
            return nil
        }
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
