import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Integración con un proceso de verdad (/bin/cat): valida la fontanería de
// pipes y el buffer de líneas juntos, sin depender de tener claude instalado.

@Test @MainActor func realProcessRoundtripTests() throws {
    try testCatEchoesLines()
    try testLongLineComesBackWhole()
}

@MainActor func testCatEchoesLines() throws {
    let lines = try runAsync { () -> [String] in
        let launcher = RealProcessLauncher()
        guard let handle = await launcher.launch(
            executable: "/bin/cat", arguments: [], cwd: nil) else { return [] }
        try await handle.sendLine("hola")
        let first = await handle.readLine()
        try await handle.sendLine(#"{"type":"result"}"#)
        let second = await handle.readLine()
        await handle.terminate()
        return [first, second].compactMap { $0 }
    }
    expectEq(lines, ["hola", #"{"type":"result"}"#],
             "cable real: cada línea vuelve entera y en orden")
}

/// La regresión que motivó el buffer: una línea más grande que cualquier
/// bloque de lectura del pipe debe volver de una pieza.
@MainActor func testLongLineComesBackWhole() throws {
    let long = String(repeating: "y", count: 20_000)
    let line = try runAsync { () -> String? in
        let launcher = RealProcessLauncher()
        guard let handle = await launcher.launch(
            executable: "/bin/cat", arguments: [], cwd: nil) else { return nil }
        try await handle.sendLine(long)
        let out = await handle.readLine()
        await handle.terminate()
        return out
    }
    expectEq(line?.count, 20_000, "cable real: 20 KB en una línea, sin cortes")
}
