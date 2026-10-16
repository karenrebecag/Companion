import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

private struct LeakyReader: ParentToolExecuting {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: "[1] button \"Nueva\"\n- tarjeta 4111 1111 1111 1111", tool: name)
    }
}

@Test func lookOutputReachesTheModelContextMasked() async {
    let tools = CompositeParentTools([LeakyReader()])
    let look = await tools.execute(name: "look", argumentsJSON: "{}")
    expect(!look.output.contains("4111"), "look: la tarjeta no pasa")
    expect(look.output.contains("[1] button"), "look: los controles siguen")
    let click = await tools.execute(name: "click", argumentsJSON: "{}")
    expect(!click.output.contains("4111"), "click: repite la etiqueta, tambien se tapa")
    expect(look.output.contains("hidden for privacy"), "look: avisa que hay valores ocultos")
}

@Test func nativeRunnerMasksWhatItReadsForBothCallers() async throws {
    let dir = NSTemporaryDirectory() + "redact-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try "tarjeta 4111 1111 1111 1111".write(toFile: dir + "/nota.txt", atomically: true, encoding: .utf8)
    let runner = NativeToolRunner(workdir: dir, places: nil)
    let read = try await runner.execute(tool: "read_file", arguments: ["path": dir + "/nota.txt"], approved: true)
    expect(read.ok && !read.output.contains("4111"), "read_file: \(read.output)")
}
