import CompanionCore
import CompanionTestKit
import Testing

// A sorted column is a promise about order. Text sorted as text puts "10"
// before "9"; empty cells must not sort as the smallest figure.

@Test func aFigureColumnSortsByValueNotAsText() {
    let rows = [["10"], ["9"], ["1,200"], ["−3"]]
    let ascending = TableSort.sorted(rows, by: .init(column: 0, direction: .ascending))
    expectEq(ascending.map { $0[0] }, ["−3", "9", "10", "1,200"],
             "columna numérica: 9 va antes que 10, y 1,200 cuenta como 1200")
    let descending = TableSort.sorted(rows, by: .init(column: 0, direction: .descending))
    expectEq(descending.map { $0[0] }, ["1,200", "10", "9", "−3"],
             "descendente invierte el orden numérico")
}

@Test func aTextColumnSortsByCollationAndEmptyCellsLast() {
    let rows = [["item 10"], [""], ["item 9"], ["Zeta"], ["alfa"]]
    let ascending = TableSort.sorted(rows, by: .init(column: 0, direction: .ascending))
    expectEq(ascending.map { $0[0] }, ["alfa", "item 9", "item 10", "Zeta", ""],
             "texto: orden natural y la celda vacía al final")
    let descending = TableSort.sorted(rows, by: .init(column: 0, direction: .descending))
    expectEq(descending.last?[0], "", "vacía al final también en descendente")
}

@Test func aColumnWithOneTextCellIsText() {
    expect(!TableSort.isNumeric(column: 0, rows: [["12"], ["doce"]]),
           "una sola celda que no es número hace la columna de texto")
    expect(!TableSort.isNumeric(column: 0, rows: [["", ""]]), "columna vacía no es numérica")
    expect(TableSort.number("NaN") == nil && TableSort.number("inf") == nil,
           "NaN e infinito no son cifras")
}

@Test func aHeaderTapStartsAscendingAndFlipsTheSameColumn() {
    let first = TableSort.tapped(nil, column: 2)
    expectEq(first, .init(column: 2, direction: .ascending), "primer toque: ascendente")
    expectEq(TableSort.tapped(first, column: 2).direction, .descending, "mismo encabezado: invierte")
    expectEq(TableSort.tapped(first, column: 0).direction, .ascending, "otra columna: empieza ascendente")
}
