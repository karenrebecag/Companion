import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 18b. The three new tools and their wire.

@Test func theBrowserHasThreeMoreToolsAllWrites() {
    expectEq(BrowserTool.open.rawValue, "browser_open", "open")
    expectEq(BrowserTool.take.rawValue, "browser_take", "take")
    expectEq(BrowserTool.release.rawValue, "browser_release", "release")
    for tool in [BrowserTool.open, .take, .release] { expect(tool.isWrite, "\(tool.rawValue) es escritura") }
    expectEq(BrowserTool.allCases.count, 12, "doce tools (H-7 P5a doble clic y clic derecho, P5b desplazar y pasar el puntero)")
}

@Test func theNewToolsSpecifyTheirArgumentsInBothLanguages() {
    for language in [AppLanguage.en, .es] {
        let open = BrowserTool.open.spec(language)
        expectEq(open.required, ["url"], "\(language): open pide url")
        expectEq(BrowserTool.take.spec(language).required, ["tab"], "\(language): take pide tab")
        expectEq(BrowserTool.release.spec(language).required, ["tab"], "\(language): release pide tab")
        expect(BrowserTool.take.spec(language).description.contains("browser_release"), "\(language): take enlaza con release")
        expect(BrowserTool.read.spec(language).description.contains("browser_take"), "\(language): read dice que exige control")
    }
}

@Test func codecEncodesOpenTakeRelease() throws {
    let cases: [(BrowserCommand, String, [String: String])] = [
        (.open(url: URL(string: "https://x.test/a")!), "browser_open", ["url": "https://x.test/a"]),
        (.take(tab: 12), "browser_take", ["tab": "12"]),
        (.release(tab: 12), "browser_release", ["tab": "12"]),
    ]
    for (command, name, want) in cases {
        let line = BrowserCodec.encode(.call(id: 4, command))
        let envelope = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let params = envelope["params"] as? [String: Any] ?? [:]
        expectEq(params["name"] as? String, name, "\(name): name")
        let args = (params["arguments"] as? [String: Any] ?? [:]).mapValues { "\($0)" }
        expectEq(args, want, "\(name): arguments")
    }
}

// H-6: the host words its reply on this flag, so it must survive decoding and default to loaded.
@Test func codecCarriesWhetherTheOpenedTabIsStillLoading() {
    let loading = #"{"id":5,"result":{"tab":{"id":123,"title":"","url":"https://x.test/","active":false,"loading":true}}}"#
    guard case .success(.opened(_, let tab)) = BrowserCodec.decode(line: loading) else { Issue.record("no tab"); return }
    expect(tab.loading, "loading survives")
    let older = #"{"id":5,"result":{"tab":{"id":123,"title":"","url":"https://x.test/","active":false}}}"#
    guard case .success(.opened(_, let plain)) = BrowserCodec.decode(line: older) else { Issue.record("no tab"); return }
    expect(!plain.loading, "an extension that does not say is taken as loaded")
}

// The host matches the navigate note exactly; a rename on either side would turn "still loading"
// back into "loaded" without any test noticing.
@Test func theStillLoadingNoteMatchesTheExtension() {
    let source = scriptText("Extensions/browser/background.js")
    expect(source.contains("const STILL_LOADING = '\(BrowserCopy.stillLoading)';"), "the extension sends the same text")
}

@Test func codecDecodesTheOpenedTab() {
    let line = #"{"id":5,"result":{"tab":{"id":123,"title":"","url":"https://x.test/","active":false}}}"#
    let want = BrowserTab(id: 123, title: "", url: "https://x.test/", active: false)
    expectEq(BrowserCodec.decode(line: line), .success(.opened(id: 5, want)), "open devuelve la pestana")
    let bad = #"{"id":5,"result":{"tab":{"title":"x"}}}"#
    guard case .failure = BrowserCodec.decode(line: bad) else { Issue.record("una pestana sin id se acepto"); return }
}

@Test func codecDecodesControlFieldsOfTabsAndDefaultsWhenAbsent() {
    let line = #"{"id":8,"result":{"tabs":[{"id":1,"title":"A","url":"https://a.test/","active":false,"controlled":true,"opener":7,"createdAt":1700000000000},{"id":2,"title":"B","url":"https://b.test/","active":true,"opener":null,"createdAt":null},{"id":3,"title":"C","url":"","active":false}]}}"#
    guard case .success(.tabs(_, let tabs)) = BrowserCodec.decode(line: line) else { Issue.record("no decodifico"); return }
    expectEq(tabs[0].controlled, true, "controlled")
    expectEq(tabs[0].opener, 7, "opener")
    expectEq(tabs[0].createdAt, Date(timeIntervalSince1970: 1_700_000_000), "createdAt en ms")
    expectEq(tabs[1].controlled, false, "ausente: false")
    expectEq(tabs[1].opener, nil, "null: nil")
    expectEq(tabs[1].createdAt, nil, "null: nil")
    expectEq(tabs[2].opener, nil, "ausente: nil")
}
