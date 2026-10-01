import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Seen live 2026-09-25: the reply's bullets read "**Seguridad:** ..." with
// the asterisks on screen. Inline marks are drawn, never shown.

@Test func markdownInlineTests() {
    let bold = MarkdownView.inline("**Clima:** el huracán se aleja")
    expectEq(String(bold.characters), "Clima: el huracán se aleja", "negrita: sin asteriscos")
    let strong = bold.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
    expect(strong, "negrita: la palabra va en negrita")
    let italic = MarkdownView.inline("por la ameba *Naegleria fowleri*.")
    expectEq(String(italic.characters), "por la ameba Naegleria fowleri.", "cursiva: sin asterisco")
    let web = MarkdownView.inline("[CNN](https://cnn.com)")
    expectEq(web.runs.first?.link, URL(string: "https://cnn.com"), "enlace web: se puede abrir")
    // Model text decides the link: only the web opens from a reply.
    let local = MarkdownView.inline("[mira](file:///etc/passwd) y [app](x-apple.systempreferences:)")
    expect(local.runs.allSatisfy { $0.link == nil }, "enlace no web: queda como texto")
    expectEq(String(MarkdownView.inline("a ** b").characters), "a ** b", "asteriscos sueltos: tal cual")
    // Security review 16j-2 (MEDIUM): a label that reads as one site must
    // not open another.
    let spoof = MarkdownView.inline("[https://mybank.com/login](http://evil-phish.example/login)")
    expect(spoof.runs.allSatisfy { $0.link == nil }, "enlace disfrazado: queda como texto")
    let bare = MarkdownView.inline("[www.mybank.com](https://evil.example)")
    expect(bare.runs.allSatisfy { $0.link == nil }, "dominio disfrazado: queda como texto")
    let honest = MarkdownView.inline("[cnn.com](https://www.cnn.com/mexico)")
    expectEq(honest.runs.first?.link?.host, "www.cnn.com", "mismo sitio: se abre")
}
