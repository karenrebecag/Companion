import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// 16p-1: a tap gesture is invisible to VoiceOver and the keyboard. Where it
// acts as a button (opens a result, picks a pin) it says so; the scrims that
// only close a sheet are not buttons and keep the sheet's own close control.

@Test @MainActor func tapSemanticsTests() async {
    testEveryTapThatActsAsAButtonSaysSo()
    testTheChainReaderFollowsClosuresAndStopsAtTheChainEnd()
    for language in [AppLanguage.en, .es] {
        let hint = Localized.string("island.reply.open", language: language)
        expect(!hint.isEmpty && !hint.contains("."),
               "island.reply.open: resuelve a texto en \(language.rawValue)")
    }
    expect(Localized.string("island.reply.open", language: .en)
           != Localized.string("island.reply.open", language: .es),
           "island.reply.open: cada idioma dice lo suyo")
}

@MainActor func testEveryTapThatActsAsAButtonSaysSo() {
    guard let root = Conformance.repoRoot() else {
        print("  nota  [tapSemantics] fuera del checkout: no hay que escanear")
        return
    }
    for name in ["Island/IslandView", "Cards/MapCard"] {
        let file = root.appendingPathComponent("Sources/CompanionUI/\(name).swift")
        guard let src = try? String(contentsOf: file, encoding: .utf8) else {
            expect(false, "\(name): el archivo se lee")
            continue
        }
        let chains = TapChains.chains(in: src)
        expect(!chains.isEmpty, "\(name): sigue habiendo un toque que revisar")
        for chain in chains {
            expect(chain.contains(".accessibilityAddTraits(.isButton)"),
                   "\(name): este onTapGesture no se anuncia como botón: \(chain.prefix(80))")
        }
    }
}

@MainActor func testTheChainReaderFollowsClosuresAndStopsAtTheChainEnd() {
    let src = """
    Foo()
        .onTapGesture {
            a()
        }
        .accessibilityAddTraits(.isButton)
    Bar()
        // .accessibilityAddTraits(.isButton) in a comment does not count
        .onTapGesture { b() }
    Baz().accessibilityAddTraits(.isButton)
    """
    let chains = TapChains.chains(in: src)
    expectEq(chains.count, 2, "lector: dos toques")
    expect(chains[0].contains(".isButton"), "lector: la cadena con botón lo ve")
    expect(!chains[1].contains(".isButton"),
           "lector: ni el comentario ni el elemento siguiente cuentan")
}

/// The modifier chain that a `.onTapGesture` belongs to: from its line to the
/// last line that still continues the chain, comments dropped.
enum TapChains {
    static func chains(in src: String) -> [String] {
        let lines = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        for (i, line) in lines.enumerated() where line.hasPrefix(".onTapGesture") {
            var chain = [line]
            var depth = balance(line)
            var j = i + 1
            while j < lines.count {
                let next = lines[j]
                if next.hasPrefix("//") { j += 1; continue }
                guard depth > 0 || next.hasPrefix(".") else { break }
                chain.append(next)
                depth += balance(next)
                j += 1
            }
            out.append(chain.joined(separator: " "))
        }
        return out
    }

    private static func balance(_ line: String) -> Int {
        line.filter { "({".contains($0) }.count - line.filter { ")}".contains($0) }.count
    }
}
