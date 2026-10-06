import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// The update is announced once: the island's card, or the window's toast when the card is suppressed.

// MARK: - Update announcement

@MainActor @Test func theUpdateIsAnnouncedOnceWhereTheUserCanSeeIt() {
    typealias Surface = UpdateAnnouncement.Surface
    func surface(front: Bool = false, hidden: Bool = false, voice: Bool = false, dismissed: String? = nil)
        -> Surface {
        UpdateAnnouncement.surface(tag: "v1", mainInFront: front, islandHidden: hidden, voiceOn: voice,
                                   dismissedTag: dismissed)
    }
    expectEq(surface(), .islandCard, "isla visible: tarjeta y NINGUN toast")
    expectEq(surface(voice: true), .islandCard, "isla visible con voz: tarjeta")
    expectEq(surface(hidden: true, voice: true), .islandCard, "isla oculta pero con voz: la tarjeta sale")
    expectEq(surface(front: true), .toast, "ventana al frente: la tarjeta se suprime, toast")
    expectEq(surface(front: true, voice: true), .toast, "ventana al frente con voz: toast")
    expectEq(surface(hidden: true), .toast, "isla oculta sin voz: toast")
    expectEq(surface(front: true, hidden: true), .toast, "ventana al frente e isla oculta: toast")
    expectEq(surface(dismissed: "v1"), .none, "version ya descartada: ni tarjeta ni toast")
    expectEq(surface(front: true, dismissed: "v1"), .none, "descartada y suprimida: sigue en silencio")
    expectEq(surface(dismissed: "v0"), .islandCard, "descartar una version no silencia la siguiente")
}

@MainActor @Test func theAnnouncementAgreesWithWhatTheIslandDraws() {
    for front in [false, true] {
        for hidden in [false, true] {
            for voice in [false, true] {
                var projection = SessionProjection()
                projection.voice = voice ? .live : .off
                let drawn = IslandState.from(projection, pebbleHidden: hidden, mainInFront: front, update: "v1")
                    .line == .updateAvailable(tag: "v1")
                let surface = UpdateAnnouncement.surface(
                    tag: "v1", mainInFront: front, islandHidden: hidden, voiceOn: voice, dismissedTag: nil)
                expectEq(surface == .islandCard, drawn, "front \(front) hidden \(hidden) voice \(voice)")
                expectEq(surface == .toast, !drawn, "toast solo cuando la isla no la dibuja")
            }
        }
    }
}

@Test @MainActor func theUpdateToastIsLocalizedInBothLanguages() async {
    for language in AppLanguage.allCases {
        await Localized.scoped(to: language) {
            let text = UpdateAnnouncement.toastText(tag: "v1.2.3")
            expect(text.contains("v1.2.3"), "\(language): lleva la version")
            expect(!text.contains("update.toast"), "\(language): la clave existe")
        }
    }
    await Localized.scoped(to: .en) {
        expect(UpdateAnnouncement.toastText(tag: "v1").contains("available"), "en: en ingles")
    }
    await Localized.scoped(to: .es) {
        expect(UpdateAnnouncement.toastText(tag: "v1").contains("disponible"), "es: en espanol")
    }
}

