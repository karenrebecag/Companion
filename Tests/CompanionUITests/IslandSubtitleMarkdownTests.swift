import CompanionCore
import CompanionTestKit
import Foundation
import Testing
@testable import CompanionUI

@Test @MainActor func theSubtitleReadsATableAndAGluedListWithoutMarkup() {
    let reply = "| Modelo | Batería |\n|---|---|\n| Pixel 10 | 5 200 mAh |\n\n3.Vierte el agua"
    expectEq(IslandReplyText.spoken(from: reply),
             "Modelo, Batería\nPixel 10, 5 200 mAh\n\n3. Vierte el agua",
             "subtitulo: sin pipes, celdas por fila, numeracion con espacio")
}
