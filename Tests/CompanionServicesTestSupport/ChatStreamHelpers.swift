import CompanionCore
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

@MainActor package func collectChat(
    _ client: ChatProviderClient,
    history: [Turn] = [Turn(role: .user, content: "hola")],
    tools: [ToolSpec] = [],
    timeout: TimeInterval = 5
) -> [ChatDelta] {
    do {
        return try runAsync(timeout: timeout) {
            var out: [ChatDelta] = []
            for try await delta in client.stream(history, tools: tools) {
                out.append(delta)
            }
            return out
        }
    } catch {
        expect(false, "stream no debía tirar \(error)")
        return []
    }
}
