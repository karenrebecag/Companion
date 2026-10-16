import CompanionCore
import CompanionTestKit
import Testing

// The counter moves only the number: "1,234.5 %" counts to 1234.5 and the
// frame stays as the model wrote it. A sparkline needs at least two real
// points, and a broken one drops the line but keeps the figure.

@Test func aFigureCountsItsNumberAndKeepsItsFrame() {
    let figure = StatsFigure("1,234.5 %")
    expectEq(figure?.number, 1234.5, "cifra con miles y decimales")
    expectEq(figure?.decimals, 1, "el número de decimales se conserva")
    expectEq(figure?.suffix, " %", "el sufijo tal como lo escribió el modelo")
    expectEq(StatsFigure("$12")?.prefix, "$", "el prefijo también")
    expect(StatsFigure("sin dato") == nil, "texto sin número no se cuenta")
}

@Test func aSparklineNeedsTwoRealPointsOrItIsDropped() {
    let good = CompanionBlocks.stats(#"{"items":[{"label":"a","value":"1","trend":[1,2,3]}]}"#)
    expectEq(good?.items.first?.trend, [1, 2, 3], "dos o más números hacen la línea")
    let single = CompanionBlocks.stats(#"{"items":[{"label":"a","value":"1","trend":[1]}]}"#)
    expect(single?.items.first?.trend == nil, "un solo punto no es una línea")
    let broken = CompanionBlocks.stats(#"{"items":[{"label":"a","value":"1","trend":[1,"x"]}]}"#)
    expect(broken?.items.first?.trend == nil, "un valor que no es número quita la línea")
    expectEq(broken?.items.first?.value, "1", "pero la cifra se queda")
}
