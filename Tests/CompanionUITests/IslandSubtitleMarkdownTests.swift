import CompanionCore
import CompanionTestKit
import Foundation
import Testing
@testable import CompanionUI

// The subtitle shows what streams as the voice says it. A document never
// streams (it travels apart, `SpokenDocument`), so markup that does slip
// into the spoken text is read as words, never as pipes or glued markers.
@Test @MainActor func theSubtitleReadsMarkupAsWordsNotSymbols() {
    expectEq(IslandReplyText.spoken(from: "Mira la **comparación**:\n\n| Modelo | Batería |\n|---|---|\n| Pixel 10 | 5 200 mAh |"),
             "Mira la comparación:\n\nModelo, Batería\nPixel 10, 5 200 mAh",
             "subtitulo: sin asteriscos ni pipes, cada fila son sus celdas")
    expectEq(IslandReplyText.spoken(from: "Primero hierve.\n3.Vierte el agua"),
             "Primero hierve.\n3. Vierte el agua",
             "subtitulo: un numero pegado no es lista y recibe su espacio")
}
