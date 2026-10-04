import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import Foundation
import SwiftUI
import Testing

// The Apps setup form and banner on Arc's bar, every phase in light and
// dark. Same harness rule as the other galleries: only with
// COMPANION_SNAPSHOTS=<dir>.

private final class RefusingApps: AppsService, @unchecked Sendable {
    func catalog(query: String, after: String?) async throws -> CatalogPage { throw AppsFailure.unauthorized }
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
@MainActor func appsSetupSnapshots() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let endpoint = "https://companion-apps.vercel.app"
    let key = String(repeating: "k", count: 64)
    var invalid = AppsSetupFlow()
    _ = invalid.submit(endpoint: "http://companion-apps.vercel.app/api", key: "short")
    var saving = AppsSetupFlow()
    _ = saving.submit(endpoint: endpoint, key: key)
    var failed = saving
    failed.finish(.serverFailed(.unauthorized))
    var confirmed = saving
    confirmed.finish(.saved)
    let cards: [(String, AppsSetupFlow, String, String)] = [
        ("form-empty", AppsSetupFlow(), "", ""),
        ("form-invalid", invalid, "http://companion-apps.vercel.app/api", "short"),
        ("form-saving", saving, endpoint, key),
        ("failed-server", failed, endpoint, key),
        ("confirmed", confirmed, endpoint, ""),
    ]
    for scheme in [ColorScheme.light, .dark] {
        let tag = scheme == .light ? "light" : "dark"
        let idle = AppsModel(
            secrets: TestSecretStore(), hostSecrets: TestHostSecretStore(),
            defaults: UserDefaults(suiteName: "apps-setup-\(UUID().uuidString)")!,
            makeService: { _, _ in RefusingApps() })
        try renderHosted(AppsPage(apps: idle), scheme: scheme, size: CGSize(width: 1000, height: 560),
                         to: out, "apps-setup-banner-\(tag)")
        for (name, flow, endpoint, key) in cards {
            try renderHosted(
                AppsSetupCard(flow: flow, endpoint: .constant(endpoint), key: .constant(key), onSubmit: {})
                    .padding(Space.x6),
                scheme: scheme, size: CGSize(width: 560, height: 560), to: out, "apps-setup-\(name)-\(tag)")
        }
    }
}

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
        Issue.record("apps-setup: \(name) could not be rendered")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        Issue.record("apps-setup: \(name) could not be encoded")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}
