import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 15b-7. Vision uploads on every press (13a), but the turn should not
// sit waiting for it unless the order actually needs the screen.
@Test @MainActor func screenNeedTests() {
    testUtteranceThatNamesTheScreenWaits()
    testOrdinaryOrderWithScreenTextDoesNotWait()
    testOrdinaryOrderWithoutScreenTextDoesNotWait()
    testOnlyAnOrderThatPointsAtTheScreenWaits()
    testEmptyUtteranceNeverWaits()
    testCuesAreAccentAndCaseInsensitive()
    testEnglishCuesAlsoWait()
}

@MainActor func testUtteranceThatNamesTheScreenWaits() {
    expectEq(ScreenNeed.wait(utterance: "¿qué dice esto?", hasText: true), .seconds(2),
             "pantalla: 'esto' pide esperar aunque ya haya texto AX")
}

@MainActor func testOrdinaryOrderWithScreenTextDoesNotWait() {
    expectEq(ScreenNeed.wait(utterance: "abre Safari", hasText: true), .zero,
             "orden ordinaria: con texto AX ya resuelto, no espera")
}

/// Wave 15g-5: no AX text is no reason to hold the brain 2 s — a late
/// vision result is carried into the next turn instead (ScreenSight).
@MainActor func testOrdinaryOrderWithoutScreenTextDoesNotWait() {
    expectEq(ScreenNeed.wait(utterance: "resume la página", hasText: false), .zero,
             "15g-5: sin texto AX, una orden que no señala la pantalla no espera")
}

/// Spec 15g §5 row 14.
@MainActor func testOnlyAnOrderThatPointsAtTheScreenWaits() {
    expectEq(ScreenNeed.wait(utterance: "abre Safari", hasText: false), .zero,
             "15g-5 fila 14: «abre Safari» sin texto AX no espera")
    expectEq(ScreenNeed.wait(utterance: "qué dice esto", hasText: false), .seconds(2),
             "15g-5 fila 14: «qué dice esto» espera 2 s")
}

@MainActor func testEmptyUtteranceNeverWaits() {
    expectEq(ScreenNeed.wait(utterance: "", hasText: false), .zero,
             "vacío: nada que resolver contra la pantalla")
    expectEq(ScreenNeed.wait(utterance: "   ", hasText: false), .zero,
             "vacío: solo espacios tampoco tiene nada que resolver")
}

@MainActor func testCuesAreAccentAndCaseInsensitive() {
    expectEq(ScreenNeed.wait(utterance: "AQUÍ qué ves", hasText: true), .seconds(2),
             "tilde y mayúsculas: 'aquí' sigue siendo la misma pista")
    expectEq(ScreenNeed.wait(utterance: "PANTALLA", hasText: true), .seconds(2),
             "mayúsculas: 'pantalla' sigue siendo la misma pista")
}

@MainActor func testEnglishCuesAlsoWait() {
    expectEq(ScreenNeed.wait(utterance: "what's on the screen", hasText: true), .seconds(2),
             "inglés: 'screen' pide esperar")
    expectEq(ScreenNeed.wait(utterance: "can you see this", hasText: true), .seconds(2),
             "inglés: 'this' pide esperar")
    expectEq(ScreenNeed.wait(utterance: "open Mail", hasText: false), .zero,
             "15g-5 inglés: sin texto AX, una orden que no señala la pantalla no espera")
    expectEq(ScreenNeed.wait(utterance: "open Mail", hasText: true), .zero,
             "inglés: orden ordinaria con texto AX, no espera")
}
