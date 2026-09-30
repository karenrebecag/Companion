import CompanionCore
import Foundation

public struct LiveCapabilityProbe: CapabilityProbe, Sendable {
    private let transport: any ChatTransport
    private let timeout: TimeInterval

    public init(transport: any ChatTransport, timeout: TimeInterval = 1) {
        self.transport = transport
        self.timeout = timeout
    }

    public func isAvailable(_ provider: ProviderDescriptor) async -> Bool {
        // Keyed providers are gated by SecretStore, not by a network ping.
        guard provider.secretKey == nil else { return true }
        // Catalog bases have no trailing slash; appendingPathComponent
        // would drop `/v1`. Concatenate like ProviderDescriptor.endpoint.
        guard let url = URL(string: provider.baseURL.absoluteString + "/models")
        else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        // Bool, not Error: a down daemon is "not here"; the router skips it.
        do {
            let (_, response) = try await transport.data(for: request)
            return response.statusCode == 200
        } catch {
            return false
        }
    }
}
