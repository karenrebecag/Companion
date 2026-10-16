@testable import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var pieces: [String] = []
    func add(_ piece: String) { lock.lock(); pieces.append(piece); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return pieces.joined() }
}

private func sseLine(_ content: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": content]]]])
    return "data: " + String(decoding: data, as: UTF8.self)
}

@Test func streamedCodeFenceKeepsItsIndentation() async throws {
    let reply = "Aquí tienes un ejemplo sencillo de saludo en Swift:\n\n```swift\nfunc greet(name: String) -> String {\n    let hello = \"Hello\"\n    return hello\n}\n```\n\nEso es todo lo necesario para empezar."
    let collected = Collected()
    let sink = DeltaSink { delta in
        if case .text(let piece) = delta { collected.add(piece) }
    }
    // Small chunks so the splitter cuts at every point it can.
    var index = reply.startIndex
    while index < reply.endIndex {
        let end = reply.index(index, offsetBy: 7, limitedBy: reply.endIndex) ?? reply.endIndex
        await sink.feed(try sseLine(String(reply[index..<end])))
        index = end
    }
    _ = await sink.finish(error: nil)
    expectEq(collected.text, reply, "el stream conserva la sangría del fence")
}
