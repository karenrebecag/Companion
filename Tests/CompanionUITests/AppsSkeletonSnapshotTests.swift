import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import Foundation
import SwiftUI
import Testing

// The Apps surface's three waiting states (catalog, the panel's actions, a
// disconnect in flight), for a human to compare against Incredible. Same
// harness rule as the other galleries: only with COMPANION_SNAPSHOTS=<dir>.

/// The catalog never answers, so the page stays on its first-load state for
/// as long as the render takes.
private final class StalledApps: AppsService, @unchecked Sendable {
    func catalog(query: String, after: String?) async throws -> CatalogPage {
        try await Task.sleep(for: .seconds(3600))
        return CatalogPage(apps: [], total: 0, next: nil)
    }
    func accounts() async throws -> [ConnectedAccount] { [] }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] { [] }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        throw AppsFailure.unexpected
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func appsLoadingSnapshots() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let app = CatalogApp(
        slug: "slack", name: "Slack",
        description: "Send messages, search channels and keep a team in the loop without leaving the conversation.",
        icon: nil)
    // English keeps the plain names the PR's before set already uses.
    for (language, suffix) in [(AppLanguage.en, ""), (.es, "-es")] {
        try await Localized.scoped(to: language) {
            for scheme in [ColorScheme.light, .dark] {
                let tag = (scheme == .light ? "light" : "dark") + suffix
                try await renderCatalogLoading(scheme: scheme, to: out, "apps-catalog-loading-\(tag)")
                for (name, phase, disconnect) in [
                    ("actions-loading", AppsModel.ActionsPhase.loading, AppsModel.DisconnectPhase.idle),
                    ("disconnecting", .ready([]), .disconnecting),
                ] {
                    try render(AppPanel(
                        app: app, state: .connected, accountName: "karen@atom.test", phase: phase,
                        disconnectPhase: disconnect, onConnect: {}, onDisconnectTapped: {},
                        onConfirmDisconnect: {}, onCancelDisconnect: {}, onClose: {}),
                               scheme: scheme, size: CGSize(width: 1000, height: 640), to: out,
                               "apps-panel-\(name)-\(tag)")
                }
            }
        }
    }
}

@MainActor private func renderCatalogLoading(scheme: ColorScheme, to out: URL, _ name: String) async throws {
    let apps = AppsModel(
        secrets: TestSecretStore(), hostSecrets: TestHostSecretStore(),
        defaults: UserDefaults(suiteName: "apps-shots-\(UUID().uuidString)")!,
        makeService: { _, _ in StalledApps() })
    #expect(apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64)))
    let loading = Task { await apps.load() }
    defer { loading.cancel() }
    // Bounded: a model that never reaches .loading must fail the gallery,
    // not hang the run.
    for _ in 0..<1000 where apps.phase != .loading { await Task.yield() }
    guard apps.phase == .loading else {
        Issue.record("apps-skeleton: \(name) never reached .loading")
        return
    }
    try renderHosted(AppsPage(apps: apps), scheme: scheme, size: CGSize(width: 1000, height: 760), to: out, name)
}

@MainActor private func render<V: View>(
    _ view: V, scheme: ColorScheme, size: CGSize, to dir: URL, _ name: String
) throws {
    let framed = view
        .frame(width: size.width, height: size.height)
        .background(Semantic.background)
        .environment(\.colorScheme, scheme)
        .environment(DropdownHost())
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else {
        Issue.record("apps-skeleton: \(name) could not be rendered")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}

/// ImageRenderer draws a ScrollView as nothing, so the page goes through a
/// hosting view and its own display pass.
@MainActor private func renderHosted<V: View>(
    _ view: V, scheme: ColorScheme, size: CGSize, to dir: URL, _ name: String
) throws {
    let framed = view
        .frame(width: size.width, height: size.height)
        .background(Semantic.background)
        .environment(\.colorScheme, scheme)
        .environment(DropdownHost())
    let host = NSHostingView(rootView: framed)
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds), !host.bounds.isEmpty else {
        Issue.record("apps-skeleton: \(name) could not be rendered")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        Issue.record("apps-skeleton: \(name) could not be encoded")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}
