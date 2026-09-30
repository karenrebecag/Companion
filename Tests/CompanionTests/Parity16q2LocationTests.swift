import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// 16q-2, decision 4: the "Tu ciudad" switch means what it says. Off, a search
// for something nearby never puts up the macOS Location dialog and never
// reads the system's city; it uses the city typed in Settings or asks.

private final class CountingSystemCity: UserLocating, @unchecked Sendable {
    private let lock = NSLock()
    private var flags: [Bool] = []
    var permissionRequests: Int { lock.withLock { flags.filter { $0 }.count } }
    var reads: Int { lock.withLock { flags.count } }
    func current(prompting: Bool) async -> UserLocation? {
        lock.withLock { flags.append(prompting) }
        return UserLocation(city: "Fullerton", country: "USA")
    }
}

private final class NearRecorder: PlacesSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String?] = []
    var nears: [String?] { lock.withLock { seen } }
    func search(_ query: String, near: String?) async -> [FoundPlace] {
        lock.withLock { seen.append(near) }
        return [FoundPlace(name: "Los Arcos", address: "Centro", lat: 18.9, lng: -99.2)]
    }
}

private func lookup(
    typed: String, channelOn: Bool, system: CountingSystemCity, places: NearRecorder
) async -> ToolResult {
    let runner = NativeToolRunner(
        workdir: NSTemporaryDirectory(), places: places,
        location: UserLocationSource(manualCity: { typed }, system: system),
        locationChannelOn: { channelOn })
    do {
        return try await runner.execute(
            tool: "find_places", arguments: ["query": "restaurantes cerca"], approved: false)
    } catch {
        expect(false, "find_places no debia tirar: \(error)")
        return ToolResult(ok: false, output: "")
    }
}

@Test func testChannelOffNeverPutsUpTheLocationDialog() async {
    let system = CountingSystemCity()
    let result = await lookup(typed: "", channelOn: false, system: system, places: NearRecorder())
    expectEq(system.permissionRequests, 0, "canal apagado: cero peticiones de permiso")
    expectEq(system.reads, 0, "canal apagado: ni siquiera se lee la ciudad del sistema")
    expect(!result.ok && result.output.lowercased().contains("ask"),
           "canal apagado y sin ciudad escrita: el modelo pregunta (needsCity) - \(result.output)")
}

@Test func testChannelOffUsesTheCityTypedInSettings() async {
    let system = CountingSystemCity()
    let places = NearRecorder()
    let result = await lookup(typed: "Cuernavaca, México", channelOn: false, system: system, places: places)
    expect(result.ok, "canal apagado con ciudad escrita: hay resultados")
    expectEq(places.nears, ["Cuernavaca, México"], "canal apagado: la busqueda lleva la ciudad de Ajustes")
    expectEq(system.reads, 0, "canal apagado: el sistema no se consulta")
}

@Test func testChannelOnKeepsTheLookupThatMayAsk() async {
    let system = CountingSystemCity()
    let places = NearRecorder()
    _ = await lookup(typed: "", channelOn: true, system: system, places: places)
    expectEq(system.permissionRequests, 1, "canal encendido: la busqueda todavia puede pedir permiso")
    expectEq(places.nears, ["Fullerton, USA"], "canal encendido: usa la ciudad del sistema")
}

@Test func testTheParentsNearMeSearchHonoursTheSwitchToo() async {
    let system = CountingSystemCity()
    let places = NearRecorder()
    let runner = ParentToolRunner(
        workspace: FakeWorkspaceOpener(), places: places,
        location: UserLocationSource(manualCity: { "" }, system: system),
        locationChannelOn: { false })
    let outcome = await runner.execute(name: "find_places", argumentsJSON: #"{"query":"restaurantes cerca"}"#)
    expectEq(system.permissionRequests, 0, "16q-2 padre: canal apagado, cero peticiones de permiso")
    expectEq(system.reads, 0, "16q-2 padre: y no se lee la ciudad del sistema")
    expect(!outcome.ok && places.nears.isEmpty, "16q-2 padre: sin ciudad escrita se pregunta y no se busca")
}
