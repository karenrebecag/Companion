import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Wave 18-4b. The panel's model holds no browser logic: it asks the host
// (through closures the composition root fills) and shows what it says.

@MainActor private final class Port {
    var status: BrowserLinkStatus = .notInstalled
    var connectResult: BrowserLinkOutcome = .done
    var removeResult: BrowserLinkOutcome = .done
    var calls: [String] = []

    func model() -> BrowserSettingsModel {
        BrowserSettingsModel(
            status: { self.status },
            connect: { self.calls.append("connect"); return self.connectResult },
            remove: { self.calls.append("remove"); return self.removeResult },
            extensionFolder: "/Applications/Companion.app/Contents/Resources/BrowserExtension",
            extensionID: "abc")
    }
}

@Test @MainActor func modelMirrorsTheHostStatusOnRefresh() {
    let port = Port()
    let model = port.model()
    model.refresh()
    expectEq(model.status, .notInstalled, "initial")
    port.status = .connected(.comet)
    model.refresh()
    expectEq(model.status, .connected(.comet), "presence change reaches the UI")
}

@Test @MainActor func connectShowsTheMoveAppNoticeAndRefreshes() {
    let port = Port()
    port.connectResult = .moveApp
    let model = port.model()
    model.connect()
    expectEq(model.notice, .moveApp, "translocated app")
    port.connectResult = .done
    port.status = .disconnected
    model.connect()
    expectEq(model.notice, nil, "a success clears the notice")
    expectEq(model.status, .disconnected, "status refreshed")
}

@Test @MainActor func removeClearsTheNoticeAndRefreshes() {
    let port = Port()
    port.status = .disconnected
    let model = port.model()
    model.refresh()
    port.status = .notInstalled
    model.remove()
    expectEq(port.calls, ["remove"], "asked the host")
    expectEq(model.status, .notInstalled, "status")
    port.removeResult = .failed
    model.remove()
    expectEq(model.notice, .failed, "a failed remove says so")
}

@Test @MainActor func everyBrowserStringExistsInBothLanguages() async {
    let keys = ["settings.browser.header", "settings.browser.blurb", "settings.browser.status.connected",
                "settings.browser.status.disconnected", "settings.browser.status.notInstalled",
                "settings.browser.connect", "settings.browser.remove", "settings.browser.folder",
                "settings.browser.id", "settings.browser.notice.moveApp", "settings.browser.notice.noBrowser",
                "settings.browser.notice.failed", "settings.browser.notice.symlink"]
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            for key in keys {
                #expect(Localized.string(key) != key, "\(key) missing in \(language)")
            }
        }
    }
}

@Test @MainActor func browserPanelIsInThePrivacyTab() {
    #expect(SettingsInventory.panels.contains { $0.tab == .privacy && $0.titleKey == "settings.browser.header" })
}
