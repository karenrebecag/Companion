import CompanionCore
import CompanionTestKit
import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 16n: the main window and the island field against Incredible, from
// docs/research/incredible-ui-detalle.md and Karen's 20:13 screenshots.

@Test @MainActor func incredibleWindowTests() {
    testHomeLayoutMatchesIncredible()
    testHeroMatchesIncredible()
    testBrandKeycapMatchesIncredible()
    testTaskRowMatchesIncredible()
    testSidebarMatchesIncredible()
    testMonogramIsTheFirstInitial()
    testIslandFieldMatchesTheScreenshot()
}

@MainActor func testHomeLayoutMatchesIncredible() {
    expectEq([HomeMetrics.maxWidth, HomeMetrics.paddingX, HomeMetrics.paddingBottom],
             [1300, 40, 64], "16n home: 1300, 40, 64")
    expectEq([HomeMetrics.headHeight, HomeMetrics.headTop], [98, 10], "16n home: cabecera 98, 10 arriba")
    expectEq([HomeMetrics.sideColumn, HomeMetrics.columnGap, HomeMetrics.tasksTop, HomeMetrics.groupGap],
             [300, 32, 40, 40], "16n home: columna 300, gap 32, tareas a 40")
}

@MainActor func testHeroMatchesIncredible() {
    expectEq([HeroMetrics.radius, HeroMetrics.paddingX, HeroMetrics.paddingY], [22, 40, 24],
             "16n banner: radio 22, 40 × 24")
    expectEq(HeroMetrics.ink.hex, "171310", "16n banner: fondo surface-ink")
    expectEq(HeroMetrics.bodyAlpha, 0.75, "16n banner: cuerpo al 75 %")
    expectEq(HeroMetrics.titleLeading, 1.25, "16n banner: título a 1.25")
    expectEq(HeroMetrics.keycapScale, 1.25, "16n banner: la tecla a 1.25 del título")
}

@MainActor func testBrandKeycapMatchesIncredible() {
    expectEq([BrandKeycap.fontScale, BrandKeycap.heightEm, BrandKeycap.minWidthEm,
              BrandKeycap.paddingEm, BrandKeycap.radiusEm], [0.54, 1.8, 2.4, 0.45, 0.45],
             "16n tecla de marca: proporciones en em")
    expectEq([BrandKeycap.border.hex, BrandKeycap.top.hex, BrandKeycap.bottom.hex],
             ["C9C9CF", "FFFFFF", "F1F1F4"], "16n tecla de marca: borde y degradado")
}

@MainActor func testTaskRowMatchesIncredible() {
    expectEq([TaskRowMetrics.paddingX, TaskRowMetrics.paddingY, TaskRowMetrics.gap],
             [18, 14, 16], "16n fila: 18 × 14, gap 16")
    expectEq([TaskRowMetrics.icon, TaskRowMetrics.chevron, TaskRowMetrics.dividerInset,
              TaskRowMetrics.listRadius, TaskRowMetrics.listPaddingY], [24, 16, 18, 22, 4],
             "16n fila: icono 24, chevron 16, divisor a 18, lista radio 22")
}

@MainActor func testSidebarMatchesIncredible() {
    expectEq(SidebarMetrics.width, 248, "16n barra: 248")
    expectEq([SidebarMetrics.logoRow, SidebarMetrics.logoLeading, SidebarMetrics.trailing],
             [44, 19, 14], "16n barra: fila del logo")
    expectEq([SidebarMetrics.itemRow, SidebarMetrics.itemHeight, SidebarMetrics.itemRadius,
              SidebarMetrics.itemPaddingX, SidebarMetrics.itemGap, SidebarMetrics.icon],
             [42, 38, 10, 12, 12, 18], "16n barra: fila de navegación")
    expectEq([SidebarMetrics.groupTop, SidebarMetrics.groupBottom, SidebarMetrics.groupLeading],
             [28, 6, 24], "16n barra: etiqueta de grupo")
    expectEq([SidebarMetrics.accountRow, SidebarMetrics.accountTrigger, SidebarMetrics.avatar,
              SidebarMetrics.chevron], [54, 42, 28, 15], "16n barra: cuenta")
    expectEq(SidebarMetrics.selectedAlpha, 0.07, "16n barra: seleccionado negro 7 %")
    expectEq(SidebarMetrics.monogramFill.hex, "C8DCF1", "16n barra: monograma cielo")
}

@MainActor func testMonogramIsTheFirstInitial() {
    expectEq(Monogram.letter("Karen Rebeca Ortiz"), "K", "16n monograma: la inicial")
    expectEq(Monogram.letter("  ana"), "A", "16n monograma: mayúscula, sin espacios")
    expectEq(Monogram.letter(""), "?", "16n monograma: sin nombre")
}

@MainActor func testIslandFieldMatchesTheScreenshot() {
    expectEq([IslandFieldMetrics.height, IslandFieldMetrics.radius, IslandFieldMetrics.textInset],
             [38, 12, 14], "16n campo: 38 de alto, radio 12, texto a 14")
    expectEq([IslandFieldMetrics.orb, IslandFieldMetrics.orbGap], [IslandGrid.lead, IslandGrid.gap], "orbe del campo: en la columna guia del grid")
    expectEq([IslandFieldMetrics.send, IslandFieldMetrics.tool, IslandFieldMetrics.trailing],
             [28, 30, 5], "16n campo: enviar 28, herramienta 30, 5 al borde")
    expectEq(IslandMetrics.rimAlpha, 0.12, "16n isla: filo blanco 12 % al abrirse")
}

// MARK: - Review 16n: behaviour, not just values

@Test @MainActor func islandHeaderBehaviourTests() {
    expectEq(IslandPopoverToggle.next(current: nil, tapped: .volume), .volume, "16n: abre el volumen")
    expectEq(IslandPopoverToggle.next(current: .volume, tapped: .volume), nil, "16n: segundo clic lo cierra")
    expectEq(IslandPopoverToggle.next(current: .volume, tapped: .menu), .menu, "16n: cambia al menú")
    expectEq(IslandEscape.action(popoverOpen: true), .closePopover, "16n: Escape cierra primero el popover")
    expectEq(IslandEscape.action(popoverOpen: false), .dismissField, "16n: luego suelta el campo")
}

@Test @MainActor func brandKeycapScalesOnceTests() {
    let previous = TypeScale.delta
    defer { TypeScale.delta = previous }
    for delta in TypeScale.min...TypeScale.max {
        TypeScale.delta = delta
        let raw = TypeSize.bannerTitle * HeroMetrics.keycapScale * BrandKeycap.fontScale
        expectEq(BrandKeycapView.em(titleSize: TypeSize.bannerTitle), TypeScale.apply(raw),
                 "16n tecla: el em es el tamaño que se pinta (delta \(delta))")
    }
}
