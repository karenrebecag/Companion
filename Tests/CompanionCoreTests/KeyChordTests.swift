import CompanionCore
import CompanionTestKit
import Foundation
import Testing

/// A shortcut is a closed list, not a free-form chord: anything the model
/// can combine would include Cmd+W and Cmd+Q, whose effect cannot be
/// verified and cannot be undone. The refusal names the menu route instead.
@Test @MainActor func keyChordTests() {
    testPlainKeysAreNotChords()
    testTheWhitelistParsesInAnyOrderAndSpelling()
    testEverythingElseIsRefusedWithAnAlternative()
    testLookalikesAndSpellingNeverMakeAChord()
    testChordsAreNamedBackCanonically()
}

@MainActor func testPlainKeysAreNotChords() {
    for raw in ["return", "tab", "escape", "up", " Return "] {
        expect(KeyChord.parse(raw) == .plain, "tecla simple: \(raw) no es un acorde")
    }
}

@MainActor func testTheWhitelistParsesInAnyOrderAndSpelling() {
    let table: [(String, Set<KeyModifier>, ChordKey)] = [
        ("cmd+n", [.command], .n),
        ("Command+F", [.command], .f),
        ("cmd + l", [.command], .l),
        ("cmd+t", [.command], .t),
        ("cmd+z", [.command], .z),
        ("cmd+shift+n", [.command, .shift], .n),
        ("shift+command+N", [.command, .shift], .n),
    ]
    for (raw, modifiers, key) in table {
        expect(KeyChord.parse(raw) == .chord(KeyChord(modifiers: modifiers, key: key)),
               "lista blanca: \(raw)")
    }
}

@MainActor func testEverythingElseIsRefusedWithAnAlternative() {
    let refused = [
        "cmd+w", "cmd+q", "cmd+h", "cmd+m", "cmd+option+esc", "ctrl+n", "cmd+x", "cmd+s",
        "option+n", "cmd+shift+z", "cmd+", "+n", "cmd+n+f", "cmd+cmd+n", "cmd+a",
        "cmd++n", "cmd+ +n", "+", "command+cmd+n", "cmd+shift+shift+n", "cmd+\tx", "cmd+return",
        "cmd+esc", "cmd+shift+cmd+n", "cmd+n+", "cmd+cmd", "shift+n", "cmd+shift+",
    ]
    for raw in refused {
        guard case .refused(let error) = KeyChord.parse(raw) else {
            expect(false, "fuera de lista: \(raw) debe rechazarse")
            continue
        }
        expectEq(error.code, "chord_not_allowed", "fuera de lista: \(raw) con su codigo")
    }
    for raw in ["cmd+w", "cmd+q", "cmd+h", "cmd+m"] {
        guard case .refused(let error) = KeyChord.parse(raw) else { continue }
        expect(error.message.contains("menu"), "\(raw): nombra el menu como alternativa")
    }
}

@MainActor func testLookalikesAndSpellingNeverMakeAChord() {
    for raw in ["cmd＋n", "cmd+ｎ", "cmd+\u{0430}", "cmd\u{200B}+n", ""] {
        let parsed = KeyChord.parse(raw)
        if case .chord = parsed { expect(false, "lookalike: \(raw.debugDescription) no es un acorde") }
    }
    expect(KeyChord.parse("CMD+SHIFT+N") == .chord(KeyChord(modifiers: [.command, .shift], key: .n)),
           "mayusculas: se aceptan")
    expect(KeyChord.parse(" cmd+n \n") == .chord(KeyChord(modifiers: [.command], key: .n)),
           "espacios alrededor: se aceptan")
    expect(KeyChord.parse("cmd＋n") == .plain, "plus de ancho completo: sin '+' ASCII es tecla suelta, y NamedKey la rechaza")
    expect((try? NamedKey.parse("cmd＋n")) == nil, "plus de ancho completo: NamedKey lo rechaza")
    expect(!KeyChord.whitelist.contains { $0.key.rawValue == "a" }, "seleccionar todo no esta en la lista")
}

@MainActor func testChordsAreNamedBackCanonically() {
    expectEq(KeyChord(modifiers: [.command, .shift], key: .n).name, "cmd+shift+n", "nombre canonico")
    expectEq(KeyChord(modifiers: [.command], key: .z).name, "cmd+z", "nombre canonico simple")
}
