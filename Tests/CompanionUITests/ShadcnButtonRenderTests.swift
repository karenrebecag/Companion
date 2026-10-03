import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// The look tables are pinned in ShadcnTokensTests; these render the style
// itself, so a modifier that stops applying the fill, border or disabled
// fade cannot pass unnoticed. The gallery is for looking at (opt-in).

@MainActor private func bitmap(_ view: some View, scheme: ColorScheme = .light) -> Data? {
    let framed = view
        .padding(Space.x4)
        .background(Semantic.background)
        .environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
}

@MainActor private func button(
    _ variant: ButtonVariant, size: ButtonSize = .default, enabled: Bool = true
) -> some View {
    Button("Label") {}
        .buttonStyle(.shadcn(variant, size: size))
        .disabled(!enabled)
}

@Test @MainActor func everyVariantRendersDistinctly() throws {
    var seen: [ButtonVariant: Data] = [:]
    for variant in ButtonVariant.allCases {
        let png = try #require(bitmap(button(variant)), "render: \(variant)")
        for (other, data) in seen {
            #expect(png != data, "\(variant) looks the same as \(other)")
        }
        seen[variant] = png
    }
}

@Test @MainActor func disabledAndSizeChangeThePixels() throws {
    let on = try #require(bitmap(button(.default)))
    let off = try #require(bitmap(button(.default, enabled: false)))
    #expect(on != off, "disabled fades the button")
    let small = try #require(bitmap(button(.default, size: .sm)))
    #expect(on != small, "size changes the box")
    let dark = try #require(bitmap(button(.default), scheme: .dark))
    #expect(on != dark, "dark inverts the solid button")
}

@Test @MainActor func appButtonKindsAreShadcnAndPillIsNot() throws {
    let kinds = try AppButtonKind.allCases.map { kind in
        try #require(bitmap(AppButton("Label", kind: kind) {}), "render: \(kind)")
    }
    #expect(Set(kinds).count == 4, "primary, secondary, destructive and ghost differ; neutral equals primary")
    let standard = try #require(bitmap(AppButton("Label") {}))
    let pill = try #require(bitmap(AppButton("Label", shape: .pill) {}))
    #expect(standard != pill, "the welcome pill keeps its own look")
}

@Test @MainActor func settingsPillsRenderEachRole() throws {
    let pills = try [SettingsPillKind.neutral, .primary, .destructive].map { kind in
        try #require(bitmap(SettingsPill(title: "Label", kind: kind, symbol: "plus") {}))
    }
    #expect(Set(pills).count == 3)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func shadcnButtonGallery() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let grid = VStack(alignment: .leading, spacing: Space.x4) {
        ForEach(ButtonSize.allCases, id: \.self) { size in
            HStack(spacing: Space.x3) {
                ForEach(ButtonVariant.allCases, id: \.self) { button($0, size: size) }
                button(.default, size: size, enabled: false)
            }
        }
        HStack(spacing: Space.x3) {
            AppButton("Cancelar", kind: .secondary) {}
            AppButton("Enviar", kind: .primary, systemImage: "paperplane") {}
            AppButton("Quitar", kind: .destructive) {}
            AppButton("Cambiar", kind: .ghost) {}
        }
        HStack(spacing: Space.x3) {
            SettingsPill(title: "Cambiar") {}
            SettingsPill(title: "Añadir", kind: .primary, symbol: "plus") {}
            SettingsPill(title: "Quitar", kind: .destructive) {}
        }
    }
    for scheme in [ColorScheme.light, .dark] {
        let png = try #require(bitmap(grid, scheme: scheme))
        try png.write(to: out.appendingPathComponent(
            "shadcn-button-\(scheme == .dark ? "dark" : "light").png"))
    }
}
