import Foundation
import Testing

@MainActor package func withTempDir(_ body: (URL) -> Void) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-conv-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        expect(false, "temp: no se pudo crear \(error)")
        return
    }
    defer { try? FileManager.default.removeItem(at: dir) }
    body(dir)
}

package func chatBody(_ request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody else { return [:] }
    do {
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    } catch {
        return [:]
    }
}

package func chatSystem(_ body: [String: Any]) -> String {
    let messages = body["messages"] as? [[String: Any]] ?? []
    return messages.first?["content"] as? String ?? ""
}
