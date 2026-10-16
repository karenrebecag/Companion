import CompanionCore
@testable import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func findPlacesTests() {
    testTheModelNeverSeesTheCoordinates()
    testTheCardCarriesWhatTheSearcherFound()
    testTheCardIsMarkedAsLookedUp()
    testNothingFoundMeansAnEmptyCard()
    testItIsSafeSoLookingUpAPlaceCostsNoClick()
    testAStreetIsNotAPlace()
}

private let soumaya = FoundPlace(
    name: "Museo Soumaya", address: "Blvd. Miguel de Cervantes Saavedra 303",
    lat: 19.4406, lng: -99.2047)

@MainActor private func run(_ places: [FoundPlace]) -> ToolResult {
    let runner = NativeToolRunner(
        workdir: NSTemporaryDirectory(), places: FakePlaces(found: places))
    do {
        return try runAsync {
            try await runner.execute(
                tool: "find_places",
                arguments: ["query": "museo soumaya"], approved: false)
        }
    } catch {
        expect(false, "find_places no debia tirar: \(error)")
        return ToolResult(ok: false, output: "")
    }
}

@MainActor func testTheModelNeverSeesTheCoordinates() {
    // El defecto de raiz: si el dato pasa por la memoria del modelo, el modelo
    // lo escribe otra vez, y esa segunda escritura es donde nace el pin en la
    // calle equivocada. Lee nombres y direcciones; con eso conversa de sobra.
    let result = run([soumaya])
    expect(result.output.contains("Museo Soumaya"), "el nombre si viaja")
    expect(result.output.contains("Cervantes"), "y la direccion tambien")
    expect(!result.output.contains("19.44"),
           "pero la latitud no: \(result.output)")
    expect(!result.output.contains("-99.20"), "ni la longitud")
}

@MainActor func testTheCardCarriesWhatTheSearcherFound() {
    guard case .locations(let block)? = run([soumaya]).card?.payload else {
        expect(false, "la tarjeta viaja por su propio canal")
        return
    }
    expectEq(block.locations.first?.lat, soumaya.lat,
             "la coordenada es la que devolvio la busqueda")
    expectEq(block.locations.first?.lng, soumaya.lng, "y la longitud")
}

@MainActor func testTheCardIsMarkedAsLookedUp() {
    expectEq(run([soumaya]).card?.source, .tool,
             "nacida de una consulta, no de la memoria de nadie")
}

@MainActor func testNothingFoundMeansAnEmptyCard() {
    // Un mapa vacio es peor que ningun mapa: parece que el sitio no existe.
    // Sin resultados se dice con una tarjeta vacia que nombra la busqueda.
    let result = run([])
    guard case .empty(.places(let query))? = result.card?.payload else {
        return expect(false, "sin resultados la tarjeta dice que no hubo lugares")
    }
    expectEq(query, "museo soumaya", "y nombra lo que se busco")
    expect(!result.ok, "y se dice que no se encontro")
}

@MainActor func testItIsSafeSoLookingUpAPlaceCostsNoClick() {
    expectEq(NativeTool.findPlaces.riskLevel, .safe,
             "consultar un lugar es leer, no tocar la Mac")
}

@MainActor func testAStreetIsNotAPlace() {
    // "cafeterias near Roma Norte" came back as "Calle Roma" alone: a road named
    // by its own address line is not somewhere to go, and it must not take a pin.
    let street = FoundPlace(
        name: "Calle Roma", address: "Calle Roma, Ciudad de México", lat: 19.42, lng: -99.16)
    let cafe = FoundPlace(
        name: "Café Toscano", address: "Álvaro Obregón 12, Roma Norte", lat: 19.419, lng: -99.163)
    guard case .locations(let block)? = run([street, cafe]).card?.payload else {
        return expect(false, "el lugar encontrado sigue en la tarjeta")
    }
    expectEq(block.locations.map(\.name), ["Café Toscano"], "la calle sale, el café se queda")
}

@Test @MainActor func cardChannelTests() async {
    // El canal completo: la tool produce, el ejecutor reenvia, y el turno que
    // vuelve al modelo NO lleva el payload. Sin este ultimo tramo el dato
    // volveria a atravesar su memoria, que es de donde veniamos.
    let runner = NativeToolRunner(
        workdir: NSTemporaryDirectory(), places: FakePlaces(found: [soumaya]))
    let result = try? await runner.execute(
        tool: "find_places", arguments: ["query": "soumaya"], approved: false)

    guard let result, let card = result.card else {
        expect(false, "la tool produjo tarjeta")
        return
    }
    expectEq(card.source, .tool, "marcada como consultada")

    // Lo que el ejecutor mete en el turno .tool es `output`, nunca `card`.
    expect(!result.output.contains("19.44"),
           "el turno que vuelve al modelo va sin coordenadas")

    // Y el evento existe para llevarla a la pantalla por su lado.
    let event = JobEvent.card(card)
    guard case .card(let carried) = event else {
        expect(false, "JobEvent transporta tarjetas")
        return
    }
    expectEq(carried, card, "sin tocar el payload por el camino")
}
