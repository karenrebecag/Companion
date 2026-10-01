import CompanionCore
import CompanionTestKit
import Testing

// 16k-2d: the seed is what the Apps page shows before any backend exists,
// so its shape is a contract — the grid, search and Conectar routing all
// assume these invariants.

@Test func catalogSeedTests() {
    let es = CatalogSeed.apps(language: .es)
    let en = CatalogSeed.apps(language: .en)
    expectEq(es.count, 12, "seed: la lista destacada trae 12 apps")
    expectEq(en.count, es.count, "seed: mismos slots en ambos idiomas")
    expectEq(Set(es.map(\.slug)).count, es.count, "seed: slugs unicos")
    expect(es.allSatisfy { $0.icon != nil }, "seed: toda app trae URL de icono")
    expect(es.allSatisfy { $0.description?.isEmpty == false }, "seed: toda app trae descripcion")

    expectEq(CatalogSeed.filtered("slack", language: .en).map(\.slug), ["slack"],
             "seed: la busqueda filtra por nombre, sin distinguir mayusculas")
    expectEq(CatalogSeed.filtered("  ", language: .es).count, es.count,
             "seed: consulta en blanco devuelve todo")
    expect(CatalogSeed.filtered("zzz", language: .es).isEmpty,
           "seed: sin coincidencia devuelve vacio")
}
