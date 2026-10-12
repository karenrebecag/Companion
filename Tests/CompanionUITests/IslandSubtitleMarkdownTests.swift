import CompanionCore
import CompanionTestKit
import Foundation
import Testing
@testable import CompanionUI

@Test @MainActor func theSubtitleSaysTheLeadAndLeavesTheTableToTheDocument() {
    let table = "Mira la comparación:\n\n| Modelo | Batería |\n|---|---|\n| Pixel 10 | 5 200 mAh |"
    expectEq(IslandReplyText.spoken(from: table), "Mira la comparación:",
             "subtitulo: la tabla es del documento, no del subtitulo")
    expectEq(IslandReplyText.spoken(from: "Primero hierve.\n3.Vierte el agua"),
             "Primero hierve.\n3. Vierte el agua",
             "subtitulo: un numero pegado no es lista y recibe su espacio")
}
