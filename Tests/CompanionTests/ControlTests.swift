import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func controlTests() {
    testPrimaryFillAndInk()
    testHoverRaisesElevation()
    testFocusedShowsTokenRing()
    testDisabledDropsOpacity()
    testDestructiveAndGhostKinds()
    testFieldErrorStroke()
    testDropdownClosesOnEscapeAndOutside()
    testDropdownArrowWrapAndChoose()
    testDropdownToggleOnEmptyStaysClosed()
    testDropdownSecondMenuClosesFirst()
    testOpenMenuSettingsPicksAreDistinct()
    testSettingsPickDoesNotArmRootHitSink()
    testRootMenusArmHitSink()
    testDropdownToggleOpensAndCloses()
    testShimmerWaitsThenSweeps()
    testShimmerActiveOnThinking()
    testShimmerRingDurations()
    testControlBarOrbSizes()
    testMuteBorderedOnlyWhenOpen()
}

@MainActor func testPrimaryFillAndInk() {
    let look = ControlLook.button(.primary, .normal)
    expectEq(look.fill, .accent, "primary: fill accent")
    expectEq(look.ink, .onAccent, "primary: ink on accent")
    expectEq(look.elevation, Elevation.rest, "primary rest: no extra shadow")
    expectEq(look.focusRing, 0, "primary rest: no ring")
    expectEq(look.opacity, 1, "primary rest: full opacity")
}

@MainActor func testHoverRaisesElevation() {
    let look = ControlLook.button(.primary, .hover)
    expectEq(look.elevation, Elevation.hover, "hover: elevation hover")
    let pressed = ControlLook.button(.primary, .pressed)
    expectEq(pressed.fill, .accent, "pressed: keeps accent fill")
}

@MainActor func testFocusedShowsTokenRing() {
    let look = ControlLook.button(.secondary, .focused)
    expectEq(look.focusRing, Stroke.medium, "focused: ring is Stroke.medium")
    expect(look.focusRing > 0, "focused: ring is visible")
    let field = ControlLook.field(.focused, error: false)
    expectEq(field.focusRing, Stroke.medium, "field focused: same ring token")
}

@MainActor func testDisabledDropsOpacity() {
    let look = ControlLook.button(.primary, .disabled)
    expect(look.opacity < 1, "disabled: faded")
    expectEq(look.focusRing, 0, "disabled: no ring")
}

@MainActor func testDestructiveAndGhostKinds() {
    let dest = ControlLook.button(.destructive, .normal)
    expectEq(dest.fill, .destructive, "destructive: fill")
    expectEq(dest.ink, .onDestructive, "destructive: ink")
    let ghost = ControlLook.button(.ghost, .normal)
    expectEq(ghost.fill, .clear, "ghost: no fill")
    expectEq(ghost.stroke, .none, "ghost: no stroke")
    let secondary = ControlLook.button(.secondary, .normal)
    expectEq(secondary.fill, .surface, "secondary: surface")
    expectEq(secondary.stroke, .border, "secondary: bordered")
}

@MainActor func testFieldErrorStroke() {
    let ok = ControlLook.field(.normal, error: false)
    expectEq(ok.stroke, .border, "field: default border")
    let err = ControlLook.field(.normal, error: true)
    expectEq(err.stroke, .destructive, "field error: destructive stroke")
    expectEq(err.focusRing, 0, "field error: ring only when focused")
}

@MainActor func testDropdownClosesOnEscapeAndOutside() {
    var session = DropdownSession(count: 3)
    session.handle(.toggle)
    expect(session.isOpen, "toggle: opens")
    session.handle(.escape)
    expect(!session.isOpen, "escape: closes")
    session.handle(.toggle)
    session.handle(.clickOutside)
    expect(!session.isOpen, "click outside: closes")
}

@MainActor func testDropdownArrowWrapAndChoose() {
    var session = DropdownSession(count: 3)
    session.handle(.toggle)
    expectEq(session.highlight, 0, "open: highlight first")
    session.handle(.arrowDown)
    expectEq(session.highlight, 1, "arrow down")
    session.handle(.arrowDown)
    session.handle(.arrowDown)
    expectEq(session.highlight, 0, "arrow down wraps")
    session.handle(.arrowUp)
    expectEq(session.highlight, 2, "arrow up wraps")
    session.handle(.choose)
    expect(!session.isOpen, "choose: closes")
    expectEq(session.lastChosen, 2, "choose: returns highlight")
}

@MainActor func testDropdownToggleOnEmptyStaysClosed() {
    var session = DropdownSession(count: 0)
    session.handle(.toggle)
    expect(!session.isOpen, "empty: stays closed")
    session.handle(.choose)
    expect(session.lastChosen == nil, "empty: no choice")
}

@MainActor func testDropdownSecondMenuClosesFirst() {
    let host = DropdownHost()
    host.present(
        .settingsPick("a"),
        items: [DropdownItem(title: "uno"), DropdownItem(title: "dos")],
        selectedTitle: "uno"
    ) { _ in }
    expect(host.session.isOpen, "primero abre")
    expect(host.menu == .settingsPick("a"), "menu a")
    host.present(
        .settingsPick("b"),
        items: [DropdownItem(title: "tres")],
        selectedTitle: "tres"
    ) { _ in }
    expect(host.session.isOpen, "segundo sigue abierto")
    expect(host.menu == .settingsPick("b"), "el segundo reemplaza al primero")
    expectEq(host.session.count, 1, "sesion del segundo")
    host.present(
        .settingsPick("b"),
        items: [DropdownItem(title: "tres")],
        selectedTitle: "tres"
    ) { _ in }
    expect(!host.session.isOpen, "mismo menu: toggle cierra")
    expect(host.menu == nil, "cerrado no deja menu")
}

@MainActor func testOpenMenuSettingsPicksAreDistinct() {
    expect(
        OpenMenu.settingsPick("Tipografía") != OpenMenu.settingsPick("Voz"),
        "settingsPick: cada campo es un menu")
    expectEq(OpenMenu.choice, OpenMenu.choice, "choice: identidad")
}

@MainActor func testSettingsPickDoesNotArmRootHitSink() {
    let host = DropdownHost()
    host.present(
        .settingsPick("a"),
        items: [DropdownItem(title: "uno")],
        selectedTitle: "uno"
    ) { _ in }
    expect(host.session.isOpen, "settingsPick abre")
    expect(!host.blocksRoot, "settingsPick no cubre la ventana raiz")
    host.dismiss()
    expect(!host.session.isOpen, "dismiss deja la sesion cerrada")
    expect(!host.blocksRoot, "cerrado no bloquea")
}

@MainActor func testRootMenusArmHitSink() {
    let host = DropdownHost()
    host.present(
        .choice,
        items: [DropdownItem(title: "nativo")],
        selectedTitle: "nativo"
    ) { _ in }
    expect(host.blocksRoot, "choice: scrim y click-away en root")
    host.present(
        .history,
        items: [DropdownItem(title: "ayer")],
        selectedTitle: "ayer"
    ) { _ in }
    expect(host.blocksRoot, "history: click-away en root")
    expect(host.menu == .history, "history reemplaza choice")
}

@MainActor func testDropdownToggleOpensAndCloses() {
    let host = DropdownHost()
    host.toggle(.choice)
    expect(host.session.isOpen, "toggle: abre choice")
    expect(host.blocksRoot, "choice: click-away en root")
    expect(host.items.isEmpty, "choice: panel propio, no items genericos")
    host.toggle(.choice)
    expect(!host.session.isOpen, "toggle otra vez: cierra")
    host.toggle(.history)
    host.toggle(.choice)
    expect(host.menu == .choice, "choice reemplaza history")
}

@MainActor func testShimmerWaitsThenSweeps() {
    expectEq(
        ShimmerMotion.phase(elapsed: 0, period: 1.5, delay: 0.25),
        0,
        "shimmer: delay holds at 0")
    expectEq(
        ShimmerMotion.phase(elapsed: 0.25, period: 1.5, delay: 0.25),
        0,
        "shimmer: sweep starts at 0")
    let mid = ShimmerMotion.phase(elapsed: 1.0, period: 1.5, delay: 0.25)
    expect(abs(mid - 0.5) < 0.001, "shimmer: (1.0-0.25)/1.5 = 0.5")
    expectEq(
        ShimmerMotion.phase(elapsed: 1.75, period: 1.5, delay: 0.25),
        0,
        "shimmer: wraps after one period")
}

@MainActor func testShimmerActiveOnThinking() {
    expect(ShimmerMotion.isActive(for: .thinking), "thinking shimmers")
    expect(ShimmerMotion.isActive(for: .connecting), "connecting shimmers")
    expect(!ShimmerMotion.isActive(for: .idle), "idle does not")
    expect(!ShimmerMotion.isActive(for: .speaking), "speaking does not")
}

@MainActor func testShimmerRingDurations() {
    expectEq(ShimmerRingMotion.thinkingDuration, 2.0,
             "ring: 2s en thinking")
    expectEq(ShimmerRingMotion.listeningDuration, 1.15,
             "ring: 1.15s en listening")
    expect(ShimmerRingMotion.thinkingBand > ShimmerRingMotion.listeningBand,
           "ring: thinking barre mas ancho")
    expect(
        OrbAppearance.shouldAnimateShell(for: .listening, reduceMotion: false)
            && OrbAppearance.shouldAnimateShell(for: .thinking, reduceMotion: false),
        "ring: listening y thinking")
    expect(
        !OrbAppearance.shouldAnimateShell(for: .idle, reduceMotion: false),
        "ring: idle sin anillo")
    expect(
        !OrbAppearance.shouldAnimateShell(for: .listening, reduceMotion: true),
        "ring: reduce-motion apaga el sweep")
}

@MainActor func testControlBarOrbSizes() {
    expectEq(ControlBarMetrics.orbVoice, 68, "orb: 68 en modo voz")
    expectEq(ControlBarMetrics.orbText, 46, "orb: 46 en modo texto")
    expectEq(ControlBarMetrics.orbSize(.voice), 68, "voz: protagonista")
    expectEq(ControlBarMetrics.orbSize(.text), 46, "texto: compacto")
}

@MainActor func testMuteBorderedOnlyWhenOpen() {
    expect(MuteChrome.bordered(muted: false),
           "mute abierto: borde, no relleno rojo")
    expect(!MuteChrome.bordered(muted: true),
           "mute cerrado: circulo rojo solido")
}
