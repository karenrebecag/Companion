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
    expect(click.output.contains("4111"), "click: no es lectura, no se toca")
}
