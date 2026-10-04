import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// S1b of the Settings brief (ajustes-hoja-incredible, signed by Karen): the
// rail and the content pane measured against the local reference
// [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967].

@Test @MainActor func theRailIsTheReferenceWidthAndInset() {
    expectEq(SettingsRailMetrics.width, 236, "ancho del rail")
    expectEq(SettingsRailMetrics.paddingTop, 12, "aire arriba")
    expectEq(SettingsRailMetrics.paddingBottom, 16, "aire abajo")
    expectEq(SettingsRailMetrics.searchPaddingX, 12, "el buscador a los lados")
    expectEq(SettingsRailMetrics.searchPaddingBottom, 24, "y debajo")
    expectEq(SettingsRailMetrics.groupGap, 28, "espaciador entre grupos")
}

@Test @MainActor func railRowsAreTheReferenceSize() {
    expectEq(SettingsRailMetrics.rowHeight, 36, "alto de fila")
    expectEq(SettingsRailMetrics.rowGap, 10, "icono a texto")
    expectEq(SettingsRailMetrics.rowPaddingX, 10, "a los lados")
    expectEq(SettingsRailMetrics.rowRadius, Radius.chip, "radio chip")
    expectEq(SettingsRailMetrics.iconSize, 18, "iconos")
    expectEq(SettingsRailMetrics.rowFontSize, TypeSize.rowTitle, "texto de fila")
    expectEq(SettingsRailMetrics.hoverDuration, 0.15, "hover")
    expectEq(SettingsRailMetrics.headingPaddingX, 10, "titulo de grupo a los lados")
    expectEq(SettingsRailMetrics.headingPaddingBottom, 6, "y debajo")
    expectEq(SettingsRailMetrics.footerPaddingX, 22, "pie a los lados")
    expectEq(SettingsRailMetrics.footerPaddingTop, 8, "y arriba")
    expectEq(SettingsRailMetrics.maxResults, 8, "tope de resultados")
}

@Test @MainActor func theContentPaneIsTheReferenceGutter() {
    expectEq(SettingsPaneMetrics.leading, 56, "gutter")
    expectEq(SettingsPaneMetrics.trailing, 96, "derecha")
    expectEq(SettingsPaneMetrics.top, 44, "cabecera arriba")
    expectEq(SettingsPaneMetrics.bottom, 40, "abajo")
    expectEq(SettingsPaneMetrics.titleSize, TypeSize.dialogTitle, "titulo de dialogo")
}

@Test @MainActor func onlyTheAccountGroupHasAHeading() async {
    let groups = SettingsTab.groups
    expectEq(groups.count, 2, "dos grupos")
    expect(groups.first?.heading == nil, "el primero sin titulo")
    expectEq(groups.map(\.pages), [SettingsTab.firstGroup, SettingsTab.secondGroup], "las mismas paginas")
    await Localized.scoped(to: .es) { expectEq(SettingsTab.groups.last?.heading, "Cuenta", "es") }
    await Localized.scoped(to: .en) { expectEq(SettingsTab.groups.last?.heading, "Account", "en") }
}

@Test @MainActor func arrowsMoveTheCursorWithoutWrapping() {
    var cursor = SettingsSearchCursor()
    expectEq(cursor.index, 0, "arranca arriba")
    cursor.move(by: -1, count: 3)
    expectEq(cursor.index, 0, "arriba no da la vuelta")
    cursor.move(by: 1, count: 3)
    cursor.move(by: 1, count: 3)
    cursor.move(by: 1, count: 3)
    expectEq(cursor.index, 2, "abajo topa en el ultimo")
    cursor.move(by: 1, count: 0)
    expectEq(cursor.index, 0, "sin resultados vuelve a cero")
}

@Test @MainActor func enterPicksTheCursorClampedToTheResults() {
    var cursor = SettingsSearchCursor()
    expect(cursor.pick(count: 0) == nil, "sin resultados no elige nada")
    expectEq(cursor.pick(count: 3), 0, "sin mover, el primero")
    cursor.move(by: 2, count: 3)
    expectEq(cursor.pick(count: 3), 2, "el que marca el cursor")
    expectEq(cursor.pick(count: 1), 0, "si la lista se acorto, el ultimo que queda")
}

@Test @MainActor func hoverMovesTheCursorAndANewQueryResetsIt() {
    var cursor = SettingsSearchCursor()
    cursor.point(at: 4, count: 5)
    expectEq(cursor.index, 4, "el hover mueve el indice")
    cursor.point(at: 9, count: 5)
    expectEq(cursor.index, 4, "un indice fuera de la lista no cuenta")
    cursor.reset()
    expectEq(cursor.index, 0, "elegir o cambiar la consulta vuelve a cero")
}

@Test @MainActor func cursorEdgesClampAndIgnoreOutOfRange() {
    var one = SettingsSearchCursor()
    one.move(by: 1, count: 1)
    expectEq(one.index, 0, "con un resultado, abajo se queda")
    one.move(by: -1, count: 1)
    expectEq(one.index, 0, "y arriba tambien")

    var big = SettingsSearchCursor()
    big.move(by: 99, count: 3)
    expectEq(big.index, 2, "un salto grande topa abajo")
    big.move(by: -5, count: 3)
    expectEq(big.index, 0, "y uno negativo grande topa arriba")
    big.move(by: 2, count: 3)
    big.move(by: 1, count: 0)
    expectEq(big.index, 0, "si los resultados se vacian, vuelve a cero")

    var hover = SettingsSearchCursor()
    hover.point(at: 2, count: 5)
    hover.point(at: -1, count: 5)
    expectEq(hover.index, 2, "una fila negativa no cuenta")
    hover.point(at: 5, count: 5)
    expectEq(hover.index, 2, "la fila justo despues del final tampoco")
    hover.point(at: 0, count: 0)
    expectEq(hover.index, 2, "sin resultados el hover no mueve")

    var shrink = SettingsSearchCursor()
    shrink.move(by: 2, count: 3)
    expectEq(shrink.pick(count: 2), 1, "de tres a dos, el ultimo")
}

// QA review S1b: the key mapping lived in the view, untested; Security
// review S1b: with a tool approval pending, Esc belongs to the approval first.
@Test @MainActor func theFieldKeysMoveClearOrPassOn() {
    var cursor = SettingsSearchCursor()
    var query = "voz"
    expect(cursor.handle(.downArrow, count: 3, query: &query, approvalPending: false), "abajo es del buscador")
    expectEq(cursor.index, 1, "y baja")
    expect(cursor.handle(.upArrow, count: 3, query: &query, approvalPending: false), "arriba tambien")
    expectEq(cursor.index, 0, "y sube")
    expect(!cursor.handle(.tab, count: 3, query: &query, approvalPending: false), "otra tecla sigue su camino")
    expect(!cursor.handle(KeyEquivalent("a"), count: 3, query: &query, approvalPending: false), "una letra se escribe")

    expect(!cursor.handle(.escape, count: 3, query: &query, approvalPending: true),
           "con una aprobacion pendiente, Esc va a la aprobacion")
    expectEq(query, "voz", "y el texto se queda")
    expect(cursor.handle(.escape, count: 3, query: &query, approvalPending: false), "sin ella, Esc con texto es del buscador")
    expectEq(query, "", "y lo limpia")
    expect(!cursor.handle(.escape, count: 3, query: &query, approvalPending: false), "vacio, Esc sigue a la hoja")

    var spaces = " "
    expect(cursor.handle(.escape, count: 0, query: &spaces, approvalPending: false), "solo espacios tambien se limpian")
    expectEq(spaces, "", "y quedan vacios")
}

@Test @MainActor func everyResultNamesItsPage() {
    for entry in SettingsInventory.searchEntries {
        let row = SettingsSearchResults.Row(entry)
        expect(!row.page.isEmpty, "\(entry.id): el pie del resultado nombra su pagina")
        expectEq(row.title, entry.title, "\(entry.id): y la etiqueta es la del ajuste")
    }
}

@Test @MainActor func resultsAreCappedAtTheReferenceCount() throws {
    let query = try #require(["a", "e", "o", "s"].first {
        SettingsSearch.match($0, in: SettingsInventory.searchEntries).count > SettingsRailMetrics.maxResults
    }, "alguna consulta corta trae mas de ocho")
    expectEq(SettingsSearchResults.rows(for: query).count, SettingsRailMetrics.maxResults, "se muestran ocho")
}

@Test @MainActor func theEmptyNoteQuotesTheQuery() async {
    await Localized.scoped(to: .es) {
        expect(SettingsSearchResults.emptyNote("zzq").contains("zzq"), "es: dice que no hay nada para lo escrito")
    }
    await Localized.scoped(to: .en) {
        expect(SettingsSearchResults.emptyNote("zzq").contains("zzq"), "en: tambien")
    }
    expect(SettingsSearchResults.rows(for: "zzzzqq").isEmpty, "una consulta sin coincidencias no trae filas")
}

@Test @MainActor func theActivePageSitsOnTheSevenPercentFill() throws {
    let on = try #require(rowPixel(selected: true))
    let off = try #require(rowPixel(selected: false))
    let rail = 0xF9
    let expected = Double(rail) * (1 - SidebarMetrics.selectedAlpha)
    expect(on.allSatisfy { abs(Double($0) - expected) < 3 }, "activa: el fondo del rail bajo negro al 7 % (\(on))")
    expect(off.allSatisfy { abs(Int($0) - rail) < 3 }, "inactiva: el fondo del rail sin relleno (\(off))")
}

@MainActor private func rowPixel(selected: Bool) -> [UInt8]? {
    let size = CGSize(width: SettingsRailMetrics.width, height: SettingsRailMetrics.rowHeight)
    let row = SettingsRailRow(page: .general, selected: selected, action: {})
        .frame(width: size.width)
        .background(Semantic.surfaceSecondary)
    let host = NSHostingView(rootView: row.environment(\.colorScheme, .light))
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds), let data = rep.bitmapData else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / size.width
    // Inside the row's leading padding: past the rounded corner, before the icon.
    let px = Int(SettingsRailMetrics.rowPaddingX / 2 * scale), py = Int(size.height / 2 * scale)
    let at = py * rep.bytesPerRow + px * rep.samplesPerPixel
    return (0..<3).map { data[at + $0] }
}

@Test @MainActor func theRailPaintsTheSelectedPageDifferently() throws {
    let general = try #require(railBitmap(.general))
    let voice = try #require(railBitmap(.voice))
    #expect(general != voice, "la pagina activa se marca")
}

@MainActor private func railBitmap(_ tab: SettingsTab) -> Data? {
    let view = SettingsSidebar(tab: .constant(tab), query: .constant(""), onPick: { _ in })
        .frame(width: SettingsRailMetrics.width, height: 600)
        .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
}
