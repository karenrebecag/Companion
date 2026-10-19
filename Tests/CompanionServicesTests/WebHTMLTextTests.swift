import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

private let exchangeFixture = """
<!DOCTYPE html>
<html lang="es">
<head>
<title>Tipo de cambio USD a MXN</title>
<style>.rate { color: red; }</style>
<script>var tracking = "function track() { return 1 }";</script>
</head>
<body>
<nav><a href="/monedas">Monedas</a> <a href="/tablas">Tablas</a></nav>
<!-- ad slot -->
<svg><path d="M0 0"/></svg>
<div class="rate">1 USD = 18,49 MXN</div>
</body>
</html>
"""

@Test func webFetchKeepsTheTextAndDropsScriptStyleNavAndMarkup() {
    let page = WebHTMLText.page(from: exchangeFixture, url: "https://xe.com/convertidor")
    expectEq(page.title, "Tipo de cambio USD a MXN", "el titulo de la pagina llega aparte")
    expect(page.text.contains("1 USD = 18,49 MXN"), "cuando la tasa esta en el texto, llega")
    for noise in ["<", ">", "function track", "color: red", "Monedas", "ad slot", "M0 0"] {
        expect(!page.text.contains(noise), "sin marcado ni codigo: no aparece \(noise)")
    }
}

@Test func webFetchDecodesEntitiesAndCollapsesWhitespace() {
    let html = "<p>Tom&nbsp;&amp;   Jerry</p>\n\n\n<p>&#36;5&#x2e;00</p>"
    let page = WebHTMLText.page(from: html, url: "https://ejemplo.pe")
    expectEq(page.text, "Tom & Jerry\n\n$5.00",
             "las entidades se decodifican y el espacio se colapsa, sin amontonar lineas vacias")
}

@Test func webFetchLeavesPlainTextAlone() {
    let body = #"{"rate": 18.49, "note": "a <b> c"}"#
    let page = WebHTMLText.page(from: body, url: "https://ejemplo.pe/api")
    expectEq(page.text, body, "lo que no es HTML no se reescribe")
}

@Test func webFetchIsCappedLikeReadURL() {
    let long = "<html><body><p>" + String(repeating: "dato ", count: 3_000) + "</p></body></html>"
    let fenced = WebText.fence(WebHTMLText.page(from: long, url: "https://ejemplo.pe"))
    expect(fenced.contains("[cut at \(ExaWebReader.maxPageCharacters) characters]"),
           "una pagina larga se corta al mismo tope que read_url, y se dice")
}
