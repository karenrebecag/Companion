import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing

// WIN-5 of the Incredible audit: Settings is a floating 336 pt panel with
// three states instead of a modal sheet.

@Test @MainActor func panelMetricsAreIncredibles() {
    expectEq(SettingsPanelMetrics.width, 336, "336 px wide")
    expectEq(SettingsPanelMetrics.radius, Radius.control, "radius 14")
    expectEq(SettingsPanelMetrics.paddingX, Space.x3_5, "padding 14 sides")
    expectEq(SettingsPanelMetrics.paddingY, Space.x3, "padding 12 top and bottom")
    expectEq(SettingsPanelMetrics.ink.hex, "16181E", "rgb(22 24 30)")
    expectEq(SettingsPanelMetrics.inkAlpha, 0.94, "at .94")
    expectEq(SettingsPanelMetrics.duration, 0.22, ".22 s")
}

@Test @MainActor func theModelStartsNormalAndNeverBlocksTheWindow() {
    let model = SettingsPanelModel()
    expectEq(model.state, .normal, "opens normal")
    expect(!model.blocksWindow, "a floating panel is not modal")
}

@Test @MainActor func dockingTogglesBetweenNormalAndDocked() {
    var model = SettingsPanelModel()
    model.toggleDock()
    expectEq(model.state, .docked, "normal docks")
    model.toggleDock()
    expectEq(model.state, .normal, "docked undocks")
}

@Test @MainActor func foldingRemembersWhereToComeBack() {
    var model = SettingsPanelModel()
    model.toggleDock()
    model.fold()
    expectEq(model.state, .folded, "docked folds")
    model.toggleDock()
    expectEq(model.state, .folded, "dock does nothing while folded")
    model.fold()
    expectEq(model.state, .folded, "folding twice is the same")
    model.unfold()
    expectEq(model.state, .docked, "unfold returns to docked")

    var plain = SettingsPanelModel()
    plain.unfold()
    expectEq(plain.state, .normal, "unfold on an open panel does nothing")
    plain.fold()
    plain.unfold()
    expectEq(plain.state, .normal, "normal folds and returns to normal")
}

@Test @MainActor func theFrameFollowsTheState() {
    let window = CGSize(width: 1120, height: 700)
    var model = SettingsPanelModel()
    let normal = model.frame(in: window)
    expectEq(normal.width, 336, "normal keeps 336")
    expectEq(normal.maxX, window.width - SettingsPanelMetrics.inset, "normal hugs the right inset")
    expectEq(normal.maxY, window.height - SettingsPanelMetrics.inset, "normal hugs the bottom inset")
    expect(normal.height <= SettingsPanelMetrics.maxHeight, "normal is capped")

    model.toggleDock()
    let docked = model.frame(in: window)
    expectEq(docked.maxX, window.width, "docked touches the right edge")
    expectEq(docked.height, window.height, "docked spans the height")
    expectEq(docked.width, 336, "docked keeps 336")

    model.fold()
    let pill = model.frame(in: window)
    expect(pill.width < 336 && pill.height < 80, "folded is a pill")
    expectEq(pill.maxX, window.width - SettingsPanelMetrics.inset, "the pill sits bottom-right")
    expectEq(pill.maxY, window.height - SettingsPanelMetrics.inset, "the pill sits bottom-right")
}

@Test @MainActor func aNarrowWindowNeverClipsThePanel() {
    let window = CGSize(width: 300, height: 240)
    let normal = SettingsPanelModel().frame(in: window)
    expect(normal.minX >= SettingsPanelMetrics.inset, "keeps its left inset")
    expect(normal.minY >= SettingsPanelMetrics.inset, "keeps its top inset")
    var docked = SettingsPanelModel()
    docked.toggleDock()
    expectEq(docked.frame(in: window).width, 300, "docked clamps to the window")
}

@Test @MainActor func cornersFollowTheState() {
    expectEq(SettingsPanelState.normal.cornerRadius, Radius.control, "normal: 14")
    expectEq(SettingsPanelState.docked.cornerRadius, 0, "docked: flush")
    expectEq(SettingsPanelState.folded.cornerRadius, Radius.full, "folded: pill")
}

@Test @MainActor func theSearchResultsListWhatMatchesAndSayWhenNothingDoes() throws {
    let known = try #require(SettingsInventory.searchEntries.first?.title, "the inventory has entries")
    expect(!SettingsSearch.match(known, in: SettingsInventory.searchEntries).isEmpty, "an entry finds itself")
    let hit = try #require(panelBitmap(SettingsSearchResults(query: known, onPick: { _ in }).frame(width: 300)))
    let none = try #require(panelBitmap(SettingsSearchResults(query: "zzzzqq", onPick: { _ in }).frame(width: 300)))
    #expect(hit != none, "matches draw rows, a miss draws the empty note")
    _ = try #require(panelBitmap(SettingsSearchField(query: .constant(""), onSubmit: {}).frame(width: 300)))
}

@MainActor private func panelBitmap(_ view: some View) -> Data? {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
}

@Test @MainActor func theFoldedPillAndHeaderPaint() throws {
    let pill = try #require(panelBitmap(SettingsPanelPill(title: "Ajustes", onExpand: {})))
    let header = try #require(panelBitmap(SettingsPanelHeader(
        title: "Ajustes", state: .normal, onDock: {}, onFold: {}, onClose: {}).frame(width: 336)))
    let docked = try #require(panelBitmap(SettingsPanelHeader(
        title: "Ajustes", state: .docked, onDock: {}, onFold: {}, onClose: {}).frame(width: 336)))
    #expect(pill != header)
    #expect(header != docked, "the dock control shows which state it will switch to")
}

@Test @MainActor func theCompactSettingsLayoutDropsTheSidebar() {
    expectEq(SettingsLayout.sheet.showsSidebar, true, "the sheet keeps its sidebar")
    expectEq(SettingsLayout.compact.showsSidebar, false, "the 336 pt panel has no room for one")
    expectEq(SettingsLayout.compact.pagePadding, Space.x3, "compact pages pad tighter")
    expectEq(SettingsLayout.sheet.pagePadding, Space.x6, "the sheet keeps its padding")
    expect(SettingsLayout.compact.showsSearch && SettingsLayout.sheet.showsSearch, "search survives in both layouts")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func settingsPanelGallery() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for state in [SettingsPanelState.normal, .docked, .folded] {
        var model = SettingsPanelModel()
        if state != .normal { model.toggleDock() }
        if state == .folded { model.fold() }
        let host = SettingsPanelHost(
            model: .constant(model), tab: .constant(.general),
            preview: nil, chat: nil, updates: nil, welcome: nil, memory: nil, browser: nil, onClose: {})
            .environment(DropdownHost())
        try await saveLive(AnyView(Color(white: 0.9).overlay { host }), scheme: .dark,
                           size: CGSize(width: 900, height: 620), to: out, "win5-panel-\(state)")
    }
}
