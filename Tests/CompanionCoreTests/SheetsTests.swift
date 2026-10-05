import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 20-3 (spec 20 D5, §6.6-7): ranges in A1 notation, values that must
// fit them, no formula that reaches the network, and every string escaped
// before it becomes an Apple Event script.

@Test func sheetsTests() {
    testA1RangesParse()
    testBadRangesAreRefused()
    testValuesMustFillTheRange()
    testValuesArriveAsJSONTextOrArrays()
    testNetworkFormulasAreRefused()
    testEveryFormulaTriggerIsChecked()
    testAppleScriptTextIsEscaped()
    testAMatrixBecomesAnAppleScriptList()
    testAFlatReadIsReshapedByColumns()
    testTheApprovalShowsWhereAndWhat()
}

func testA1RangesParse() {
    let range = SheetRange(a1: "b2:d5")
    expectEq(range?.a1, "B2:D5", "rango: se normaliza a mayúsculas")
    expectEq(range?.rows, 4, "rango: filas")
    expectEq(range?.columns, 3, "rango: columnas")
    expectEq(SheetRange(a1: "AA10")?.columns, 1, "rango: una celda con dos letras")
    expectEq(SheetRange(a1: "AA10")?.firstColumn, 27, "rango: AA es la 27")
    expectEq(SheetRange(a1: "D5:B2")?.a1, "B2:D5", "rango: invertido se ordena")
    expectEq(SheetRange(a1: "B2:D5")?.cell(row: 1, column: 2), "D3", "rango: celda por índice")
}

func testBadRangesAreRefused() {
    for bad in ["", "A", "1", "A0", "A1:", "A1:B", "Sheet1!A1", "A1;B2", "ZZZZ1", "A1:A99999999"] {
        expect(SheetRange(a1: bad) == nil, "rango inválido: \(bad)")
    }
    expect(SheetRange(a1: "A1:Z1000") == nil, "rango: más de \(SheetRange.maxCells) celdas se rechaza")
}

func testValuesMustFillTheRange() {
    guard let range = SheetRange(a1: "A1:B2") else { return expect(false, "rango") }
    let ok = SheetValues.parse(any: [["a", 1], ["b", 2.5]], for: range)
    guard case .success(let cells) = ok else { return expect(false, "valores: 2×2 caben") }
    expectEq(cells[0][1], .number(1), "valores: número")
    expectEq(cells[1][0], .text("b"), "valores: texto")
    guard case .failure(let error) = SheetValues.parse(any: [["a"]], for: range) else {
        return expect(false, "valores: 1×1 en un 2×2 no cabe")
    }
    expectEq(error, .shapeMismatch, "valores: el error dice que no cabe")
}

func testValuesArriveAsJSONTextOrArrays() {
    guard let range = SheetRange(a1: "A1:A2") else { return expect(false, "rango") }
    guard case .success(let cells) = SheetValues.parse(any: #"[["=SUM(B1:B3)"],[null]]"#, for: range) else {
        return expect(false, "valores: JSON en texto")
    }
    expectEq(cells[0][0], .formula("=SUM(B1:B3)"), "valores: una fórmula empieza con =")
    expectEq(cells[1][0], .empty, "valores: null deja la celda vacía")
}

func testNetworkFormulasAreRefused() {
    guard let range = SheetRange(a1: "A1") else { return expect(false, "rango") }
    for formula in ["=WEBSERVICE(\"https://x\")", "=importxml(A1,\"//a\")", "=IMPORTDATA(A1)", "=IMPORTHTML(A1)",
                    "=FILTERXML(A1,\"x\")", "=cmd|' /c calc'!A0", "=HYPERLINK(\"file:///etc\")", "=CALL(\"x\")"] {
        guard case .failure(let error) = SheetValues.parse(any: [[formula]], for: range) else {
            return expect(false, "fórmula de red aceptada: \(formula)")
        }
        expectEq(error, .forbiddenFormula, "fórmula rechazada: \(formula)")
    }
    guard case .success = SheetValues.parse(any: [["=SUM(A2:A9)*2"]], for: range) else {
        return expect(false, "una fórmula normal pasa")
    }
}

/// Security review 20 (CRITICAL): Excel's formula setter reads `+`, `-` and
/// `@` like `=`, so a poisoned cell must not dodge the list by its first char.
func testEveryFormulaTriggerIsChecked() {
    guard let range = SheetRange(a1: "A1") else { return expect(false, "rango") }
    for payload in ["+cmd|' /C calc'!A0", "-cmd|' /C calc'!A0", "@WEBSERVICE(\"http://x\")",
                    "+HYPERLINK(\"http://x\")", " =WEBSERVICE(\"http://x\")",
                    "=\u{FF37}EBSERVICE(\"http://x\")", "=WEBSERVICE\u{00A0}(\"http://x\")"] {
        guard case .failure(let error) = SheetValues.parse(any: [[payload]], for: range) else {
            return expect(false, "fórmula disfrazada aceptada: \(payload)")
        }
        expectEq(error, .forbiddenFormula, "fórmula disfrazada rechazada: \(payload)")
    }
    for fine in ["-12 grados", "+52 55 1234", "@karen", "a|b"] {
        guard case .success = SheetValues.parse(any: [[fine]], for: range) else {
            return expect(false, "un texto inocente pasa: \(fine)")
        }
    }
}

func testAppleScriptTextIsEscaped() {
    expectEq(AppleScriptText.literal("a\"b"), #""a\"b""#, "AppleScript: una comilla se escapa")
    expectEq(AppleScriptText.literal("a\\b"), #""a\\b""#, "AppleScript: una barra se escapa")
    let hostile = "x\" & (do shell script \"rm -rf ~\") & \""
    let lit = AppleScriptText.literal(hostile)
    expect(lit.hasPrefix("\"") && lit.hasSuffix("\""), "AppleScript: sigue siendo un solo literal")
    let inner = lit.dropFirst().dropLast()
    var escaped = false
    for char in inner {
        if escaped { escaped = false; continue }
        if char == "\\" { escaped = true; continue }
        expect(char != "\"", "AppleScript: ninguna comilla sin escapar cierra el literal")
    }
    expect(!AppleScriptText.literal("a\nb").contains("\n"), "AppleScript: un salto de línea no parte el script")
}

func testAMatrixBecomesAnAppleScriptList() {
    let list = AppleScriptText.matrix([[.text("a"), .number(1.5)], [.formula("=A1"), .empty]])
    expectEq(list, #"{{"a", 1.5}, {"=A1", ""}}"#, "AppleScript: lista de listas")
    expectEq(AppleScriptText.matrix([[.number(3)]]), "{{3}}", "AppleScript: un entero sin .0")
}

func testAFlatReadIsReshapedByColumns() {
    expectEq(SheetValues.reshape(["a", "b", "c", "d", "e", "f"], columns: 3), [["a", "b", "c"], ["d", "e", "f"]],
             "lectura plana de Numbers: filas de tantas columnas como el rango")
    expectEq(SheetValues.reshape(["a"], columns: 3), [["a", "", ""]], "lectura corta: se rellena")
}

func testTheApprovalShowsWhereAndWhat() {
    let detail = SheetValues.approvalDetail(["app": "excel", "range": "B2:C3", "values": #"[["a",1],["b",2]]"#])
    expect(detail?.contains("B2:C3") == true, "hoja: la aprobación dice el rango")
    expect(detail?.contains("a") == true, "hoja: y lo que se va a escribir")
}
