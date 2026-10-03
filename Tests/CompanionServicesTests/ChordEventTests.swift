import ApplicationServices
import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

/// The event a chord becomes carries exactly the modifiers asked for and the
/// physical key of its letter, nothing the user happens to be holding.
@Test @MainActor func chordEventTests() {
    expectEq(AXTextInjector.flags(for: [.command]), CGEventFlags.maskCommand, "cmd: solo Command")
    expectEq(AXTextInjector.flags(for: [.command, .shift]),
             CGEventFlags([.maskCommand, .maskShift]), "cmd+shift: exactamente esos dos")
    expectEq(AXTextInjector.flags(for: []), CGEventFlags([]), "sin modificadores: sin flags")
    expectEq(AXTextInjector.flags(for: [.option]), CGEventFlags.maskAlternate, "option: solo Option")
    expectEq(AXTextInjector.flags(for: [.control]), CGEventFlags.maskControl, "control: solo Control")
    let table: [ChordKey: CGKeyCode] = [.n: 45, .f: 3, .l: 37, .t: 17, .z: 6]
    for key in ChordKey.allCases {
        expectEq(AXTextInjector.keyCode(key), table[key], "\(key): su tecla ANSI")
    }
    // W, Q, H and M close, quit, hide and minimise: no whitelisted chord may land on them.
    let destructive: Set<CGKeyCode> = [13, 12, 4, 46]
    expect(ChordKey.allCases.allSatisfy { !destructive.contains(AXTextInjector.keyCode($0)) },
           "ninguna letra de la lista cae en W, Q, H ni M")
    expect(!AXScreen.isEnabled(0), "AXEnabled 0: deshabilitado")
    expect(AXScreen.isEnabled(1), "AXEnabled 1: habilitado")
    expect(AXScreen.isEnabled(nil), "sin AXEnabled: habilitado")
    expectEq(AXScreen.pageAction(.left), "AXScrollLeftByPage", "izquierda: accion de pagina")
    expectEq(AXScreen.pageAction(.right), "AXScrollRightByPage", "derecha: accion de pagina")
    expectEq(AXScreen.pageAction(.intoView), "AXScrollToVisible", "into_view: accion de visibilidad")
}
