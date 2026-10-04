import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// S1c of the Settings brief (ajustes-hoja-incredible, signed by Karen): a
// search pick opens the page, finds the row, centres it and lays a band
// behind it, as the local reference does
// [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967].

@Test @MainActor func theBandTimingIsTheReferences() {
    expectEq(SettingsSearchJump.fadeIn, 0.3, "entra en 300 ms")
    expectEq(SettingsSearchJump.hold, 1.1, "se queda 1100 ms")
    expectEq(SettingsSearchJump.fadeOut, 0.35, "se apaga en 350 ms")
    expectEq(SettingsSearchJump.bandOutset, 6, "sobresale 6 arriba y abajo")
    expectEq(SettingsSearchJump.attempts, 20, "busca la fila hasta 20 veces")
    expectEq(SettingsSearchJump.retryInterval, 0.05, "cada 50 ms")
}

@Test @MainActor func pageEntriesOpenThePageWithoutScrollOrBand() {
    let page = SettingsSearch.Entry(id: "settings.tab.system", page: "system", title: "Sistema", subtitle: "")
    expect(SettingsSearchJump.target(for: page) == nil, "una entrada de pagina no busca fila")
    let row = SettingsSearch.Entry(id: "settings.sounds", page: "general", title: "Sonidos", subtitle: "")
    expectEq(SettingsSearchJump.target(for: row), "settings.sounds", "una entrada de fila busca su fila")
}

@Test @MainActor func everyPageEntryInTheInventoryIsAPageEntry() {
    for tab in SettingsTab.allCases {
        let entry = SettingsInventory.searchEntries.first { $0.id == "settings.tab.\(tab.rawValue)" }
        expect(entry != nil, "\(tab): tiene su entrada de pagina")
        expect(entry.flatMap(SettingsSearchJump.target(for:)) == nil, "\(tab): y no hace scroll")
    }
}

@Test @MainActor func theSearchRetriesUntilTheRowAppearsThenStops() {
    var jump = SettingsSearchJump(target: "settings.sounds")
    expectEq(jump.poll(present: []), .wait, "la pagina aun no pinta la fila: espera")
    expectEq(jump.poll(present: ["settings.sounds"]), .found("settings.sounds"), "aparece: la centra")
    expectEq(jump.poll(present: ["settings.sounds"]), .done, "una vez hallada no repite el scroll")
}

@Test @MainActor func theSearchGivesUpAfterItsAttempts() {
    var jump = SettingsSearchJump(target: "settings.missing")
    for attempt in 1 ..< SettingsSearchJump.attempts {
        expectEq(jump.poll(present: []), .wait, "intento \(attempt): espera")
    }
    expectEq(jump.poll(present: []), .done, "al vigesimo se rinde: la pagina queda abierta, sin banda")
    expectEq(jump.poll(present: ["settings.missing"]), .done, "y ya no la busca aunque aparezca tarde")
}

@Test @MainActor func pollFindsOnTheFirstAndOnTheLastTry() {
    var first = SettingsSearchJump(target: "k")
    expectEq(first.poll(present: ["k"]), .found("k"), "la pagina ya estaba: al primer intento")
    expectEq(first.poll(present: ["k"]), .done, "y una sola vez")

    var last = SettingsSearchJump(target: "k")
    for _ in 1 ..< SettingsSearchJump.attempts { _ = last.poll(present: []) }
    expectEq(last.poll(present: ["k"]), .found("k"), "al vigesimo intento todavia la encuentra")

    var flicker = SettingsSearchJump(target: "k")
    expectEq(flicker.poll(present: ["k"]), .found("k"), "aparece")
    expectEq(flicker.poll(present: []), .done, "si desaparece no vuelve a buscar")
    expectEq(flicker.poll(present: ["k"]), .done, "ni la centra otra vez")
}

@Test @MainActor func theBandPlaysInHoldsAndGoesOut() {
    let steps = SettingsSearchJump.bandSteps
    expectEq(steps.map(\.visible), [true, false], "primero se enciende, despues se apaga")
    expectEq(steps.map(\.fade), [0.3, 0.35], "entra en 300 y se apaga en 350")
    expect(abs(steps[0].wait - 1.4) < 1e-9, "encendida espera 300 + 1100 antes de apagarse")
    expect(abs(steps[1].wait - 0.35) < 1e-9, "y el apagado termina antes de soltar la banda")
}

// Code and QA review S1c: an inventory entry no row carried polled for a
// second and did nothing.
@Test @MainActor func everySearchEntryHasARowToLandOn() throws {
    let pages: [SettingsTab: AnyView] = [
        .general: AnyView(SettingsGeneralPage(accessibility: nil, onLanguageChange: {})),
        .voice: AnyView(SettingsVoiceSection(preview: nil)),
        .vocabulary: AnyView(SettingsVocabularyPage()),
        .memory: AnyView(SettingsMemoryPage(memory: nil)),
        .you: AnyView(SettingsYouPage()),
        // Production always passes these two; their cards are what the entries name.
        .privacy: AnyView(SettingsPrivacyPage(chat: nil, welcome: quietWelcome(), browser: quietBrowser())),
        .system: AnyView(SettingsSystemPage(
            chat: nil, updates: nil, welcome: quietWelcome(), storageLabel: "", confirmPurge: .constant(false),
            onClose: {}, onAppear: {})),
    ]
    for tab in SettingsTab.allCases {
        let view = try #require(pages[tab], "\(tab): la prueba monta la pagina")
        let mounted = mountedKeys(view)
        let wanted = SettingsInventory.searchEntries.filter { $0.page == tab.rawValue }
            .compactMap(SettingsSearchJump.target(for:))
        for key in wanted {
            expect(mounted.contains(key), "\(tab): \(key) tiene una fila donde caer (montadas: \(mounted.sorted()))")
        }
    }
}

@MainActor private final class KeyBox { var keys: Set<String> = [] }

private final class QuietDevices: WelcomeDevices, @unchecked Sendable {
    func granted(_ permission: WelcomePermission) async -> Bool { false }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { false }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
}

@MainActor private func quietWelcome() -> WelcomeModel {
    let defaults = UserDefaults(suiteName: "s1c-jump-\(UUID().uuidString)") ?? .standard
    return WelcomeModel(devices: QuietDevices(), keyReady: { true }, defaults: defaults)
}

@MainActor private func quietBrowser() -> BrowserSettingsModel {
    BrowserSettingsModel(
        status: { .notInstalled }, connect: { .done }, remove: { .done },
        extensionFolder: "/tmp/ext", extensionID: "abc")
}

@MainActor private func mountedKeys(_ page: AnyView) -> Set<String> {
    let box = KeyBox()
    let view = page
        .frame(width: 800)
        .onPreferenceChange(SettingsRowKeys.self) { box.keys = $0 }
        .environment(DropdownHost())
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(x: 0, y: 0, width: 800, height: 4000)
    // Preferences settle only for a view in a window; far off screen it never shows.
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    return box.keys
}

@Test @MainActor func theBandLightsTheRowAndReachesSixPastIt() throws {
    for kind in [BandRow.plain, .text] {
        let lit = try #require(bandPixels(SettingsBand(key: "k", visible: true), kind))
        let off = try #require(bandPixels(SettingsBand(key: "k", visible: false), kind))
        let other = try #require(bandPixels(SettingsBand(key: "otra", visible: true), kind))
        let washed = 255 * (1 - StateAlpha.active)
        func wash(_ px: [UInt8]) -> Bool { px.allSatisfy { abs(Double($0) - washed) < 3 } }
        func clear(_ px: [UInt8]) -> Bool { px.allSatisfy { $0 > 252 } }
        expect(wash(lit.inside), "\(kind) encendida: la fila bajo la banda (\(lit.inside))")
        expect(wash(lit.aboveIn) && wash(lit.belowIn), "\(kind): sobresale hasta 6 arriba y abajo")
        expect(clear(lit.aboveOut) && clear(lit.belowOut), "\(kind): y no mas alla de 6")
        expect(clear(off.inside), "\(kind): apagada no pinta")
        expect(clear(other.inside), "\(kind): la banda de otra fila no pinta esta")
    }
}

private enum BandRow { case plain, text }

private struct BandShot {
    let inside, aboveIn, aboveOut, belowIn, belowOut: [UInt8]
}

@MainActor private func bandPixels(_ band: SettingsBand, _ kind: BandRow) -> BandShot? {
    let margin: CGFloat = 20
    let width: CGFloat = 300
    let row: AnyView = switch kind {
    case .plain: AnyView(SettingsRow(title: "Sonidos", key: "k") { EmptyView() })
    case .text: AnyView(SettingsTextRow(title: "Sobre ti", key: "k", placeholder: "", text: .constant("")))
    }
    let rowHeight = NSHostingView(rootView: row.frame(width: width - 2 * margin)).fittingSize.height
    let size = CGSize(width: width, height: rowHeight + 2 * margin)
    let view = row
        .frame(width: width - 2 * margin)
        .padding(margin)
        .background(Color.white)
        .environment(\.settingsBand, band)
        .environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let data = rep.bitmapData else { return nil }
    let scale = CGFloat(rep.pixelsWide) / size.width
    func at(_ y: CGFloat) -> [UInt8] {
        let o = Int(y * scale) * rep.bytesPerRow + Int((margin + 4) * scale) * rep.samplesPerPixel
        return (0..<3).map { data[o + $0] }
    }
    let top = margin, bottom = margin + rowHeight
    // Literal 6: the band's reach is the reference's, not whatever the constant says.
    // Sampled at the edge itself: the 6th point out is lit, the 7th is not.
    return BandShot(inside: at(top + 4), aboveIn: at(top - 6), aboveOut: at(top - 7),
                    belowIn: at(bottom + 5), belowOut: at(bottom + 6))
}
