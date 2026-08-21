import CompanionCore
import Foundation
import Testing

// El bug que esto reemplaza: el cable real leía bloques de 4096 bytes y los
// trataba como "una línea", así que el NDJSON llegaba partido o pegado.

@Test @MainActor func lineBufferTests() {
    testFeedWholeLine()
    testLineSplitAcrossChunks()
    testSeveralLinesInOneChunk()
    testLongLineSurvivesChunking()
    testRemainderFlushesAtEOF()
    testEmptyLinesAreSkipped()
}

@MainActor func testFeedWholeLine() {
    var buf = LineBuffer()
    let lines = buf.feed(Data("{\"a\":1}\n".utf8))
    expectEq(lines, ["{\"a\":1}"], "una línea completa sale entera")
}

@MainActor func testLineSplitAcrossChunks() {
    var buf = LineBuffer()
    let first = buf.feed(Data("{\"type\":\"res".utf8))
    let second = buf.feed(Data("ult\"}\n".utf8))
    expectEq(first, [], "media línea se retiene hasta su salto")
    expectEq(second, ["{\"type\":\"result\"}"], "el resto completa la línea")
}

@MainActor func testSeveralLinesInOneChunk() {
    var buf = LineBuffer()
    let lines = buf.feed(Data("uno\ndos\ntr".utf8))
    expectEq(lines, ["uno", "dos"], "dos líneas salen, la tercera espera")
    expectEq(buf.feed(Data("es\n".utf8)), ["tres"], "la cola se completa después")
}

/// Una respuesta de result puede medir decenas de KB: mucho más que
/// cualquier bloque de lectura del pipe.
@MainActor func testLongLineSurvivesChunking() {
    var buf = LineBuffer()
    let long = String(repeating: "x", count: 20_000)
    var out: [String] = []
    let data = Data((long + "\n").utf8)
    var offset = 0
    while offset < data.count {
        let end = min(offset + 4096, data.count)
        out += buf.feed(data.subdata(in: offset..<end))
        offset = end
    }
    expectEq(out.count, 1, "la línea larga sale como una sola")
    expectEq(out.first?.count, 20_000, "sin perder un byte")
}

@MainActor func testRemainderFlushesAtEOF() {
    var buf = LineBuffer()
    _ = buf.feed(Data("sin salto final".utf8))
    expectEq(buf.flush(), "sin salto final", "EOF entrega lo que quedó")
    expectEq(buf.flush(), nil, "flush es de una sola vez")
}

@MainActor func testEmptyLinesAreSkipped() {
    var buf = LineBuffer()
    let lines = buf.feed(Data("\n\nuno\n\n".utf8))
    expectEq(lines, ["uno"], "líneas vacías no llegan al parser")
}
