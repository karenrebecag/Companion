import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// QA 606: after a map card the model's last assistant word was "Se mostró un
// mapa con: X", and its reply repeated that one name. The recall now carries
// every place with its address, and never a coordinate.
@Test @MainActor func aMapRecallListsEveryPlaceWithoutCoordinates() {
    let block = LocationsBlock(title: "cafeterías", locations: [
        LocationsBlock.Location(id: nil, name: "Paradigma Café", eyebrow: nil,
                                address: "Colima 100", lat: 19.4190, lng: -99.1600, url: nil),
        LocationsBlock.Location(id: nil, name: "Buna", eyebrow: nil,
                                address: nil, lat: 19.4201, lng: -99.1612, url: nil),
    ])
    let recall = ChatCopy.cardRecall(Card(payload: .locations(block), source: .tool))
    expectEq(recall, ChatCopy.cardShown(Card(payload: .locations(block), source: .tool))
             + " Paradigma Café — Colima 100; Buna",
             "qa606: el recall lista los lugares con su dirección")
    expect(!recall.contains("19.4"), "qa606: ninguna coordenada entra al recall")
}
