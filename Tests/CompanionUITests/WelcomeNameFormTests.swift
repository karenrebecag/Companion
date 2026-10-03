import AppKit
import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing
@testable import CompanionUI

// The welcome's name page (Companion's `hello` step): form width, the 50 pt
// field, and its focus look.

@Test @MainActor func welcomeNameFormTests() async {
    testTheFormIsThreeFortyWideAndShrinksWithTheColumn()
    testWidthSurvivesNonFiniteInput()
    testTheFieldIsFiftyHigh()
    testTheFocusedFieldHasTheThreePointHalo()
    testTheFieldFillFollowsHoverAndFocus()
    testFocusDrawsTheBorderInInk()
    testTheFieldAnimatesUnlessReduceMotion()
    testTheWashesAreDistinctFromTheBackgroundInBothSchemes()
    await testTheLayoutAtTheMinimumWindow()
    await testTheFormStaysCappedAndCenteredOnWiderWindows()
}

@MainActor func testTheFormIsThreeFortyWideAndShrinksWithTheColumn() {
    expectEq(NameFormLayout.width(available: 520), 340, "name: columna ancha, el formulario topa en 340")
    expectEq(NameFormLayout.width(available: 340), 340, "name: justo en el tope")
    expectEq(NameFormLayout.width(available: 300), 300, "name: columna angosta, el formulario la sigue")
    expectEq(NameFormLayout.width(available: 0), 0, "name: sin espacio, sin ancho")
    expectEq(NameFormLayout.width(available: -12), 0, "name: nunca negativo")
}

@MainActor func testWidthSurvivesNonFiniteInput() {
    expectEq(NameFormLayout.width(available: .nan), 0, "name: NaN no ensancha ni rompe el layout")
    expectEq(NameFormLayout.width(available: .infinity), 340, "name: propuesta infinita topa en 340")
    expectEq(NameFormLayout.width(available: -.infinity), 0, "name: -infinito es 0")
}

@MainActor func testTheFieldIsFiftyHigh() {
    expectEq(ControlMetrics.nameFieldHeight, 50, "name: .fr-name-input height")
    expectEq(Container.nameForm, 340, "name: .fr-name-form tope")
}

@MainActor func testTheFocusedFieldHasTheThreePointHalo() {
    expectEq(NameFieldLook.resolve(focused: true, hovering: false).halo, Stroke.ring, "name: foco = halo de 3")
    expectEq(NameFieldLook.resolve(focused: true, hovering: true).halo, Stroke.ring, "name: foco gana al hover")
    expectEq(NameFieldLook.resolve(focused: false, hovering: false).halo, 0, "name: sin foco no hay halo")
    expectEq(NameFieldLook.resolve(focused: false, hovering: true).halo, 0, "name: hover no pinta halo")
}

@MainActor func testTheFieldFillFollowsHoverAndFocus() {
    expectEq(NameFieldLook.resolve(focused: false, hovering: false).fill, .rest, "name: reposo")
    expectEq(NameFieldLook.resolve(focused: false, hovering: true).fill, .hover, "name: hover")
    expectEq(NameFieldLook.resolve(focused: true, hovering: true).fill, .focused, "name: foco")
}

/// Focus must clear 3:1 non-text contrast, which the 10 % halo alone does not.
@MainActor func testFocusDrawsTheBorderInInk() {
    let rest = NameFieldLook.resolve(focused: false, hovering: false)
    let hover = NameFieldLook.resolve(focused: false, hovering: true)
    let focus = NameFieldLook.resolve(focused: true, hovering: false)
    expect(focus.border != rest.border, "name: el borde en foco difiere del de reposo")
    expect(focus.border != hover.border, "name: el borde en foco difiere del de hover")
    expectEq(focus.border, .ink, "name: el borde enfocado es tinta, como el aro de AppField")
    expectEq(NameFieldLook.resolve(focused: true, hovering: true).border, .ink, "name: foco gana al hover")
}

// The reduce-motion wiring and a focused render are not tested: the first is
// environment wiring an offscreen host cannot flip, and @FocusState needs a
// key window, which an offscreen host does not give reliably. The halo
// geometry is covered by the side-margin assertion below.
@MainActor func testTheFieldAnimatesUnlessReduceMotion() {
    expect(NameFieldLook.animation(reduceMotion: false) != nil, "name: anima el cambio de foco")
    expect(NameFieldLook.animation(reduceMotion: true) == nil, "name: con reduce motion el cambio es instantaneo")
}

/// A wash over the page, composited, as the eye sees it.
private func composite(_ color: Color, over background: Color, _ name: NSAppearance.Name) -> [CGFloat] {
    var out: [CGFloat] = []
    NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
        let top = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        let base = NSColor(background).usingColorSpace(.sRGB) ?? .clear
        let a = top.alphaComponent
        out = [
            top.redComponent * a + base.redComponent * (1 - a),
            top.greenComponent * a + base.greenComponent * (1 - a),
            top.blueComponent * a + base.blueComponent * (1 - a),
        ]
    }
    return out
}

private func distinct(_ a: [CGFloat], _ b: [CGFloat]) -> Bool {
    zip(a, b).contains { abs($0 - $1) > 0.01 }
}

@MainActor func testTheWashesAreDistinctFromTheBackgroundInBothSchemes() {
    for name in [NSAppearance.Name.aqua, .darkAqua] {
        let page = composite(Semantic.background, over: Semantic.background, name)
        let rest = composite(Semantic.fieldWash, over: Semantic.background, name)
        let hover = composite(Semantic.fieldWashHover, over: Semantic.background, name)
        expect(distinct(rest, page), "name: el campo en reposo se distingue del fondo (\(name.rawValue))")
        expect(distinct(hover, page), "name: el campo en hover se distingue del fondo (\(name.rawValue))")
        expect(distinct(hover, rest), "name: hover se distingue de reposo (\(name.rawValue))")
    }
}

// MARK: the real WelcomeView, measured through the frame seam

private final class SilentDevices: WelcomeDevices, @unchecked Sendable {
    func granted(_ permission: WelcomePermission) async -> Bool { false }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { false }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
}

@MainActor private final class Frames { var value: [WelcomeFrameRole: CGRect] = [:] }

@MainActor private func helloView() -> some View {
    let defaults = UserDefaults(suiteName: "gap6-name-\(UUID().uuidString)") ?? .standard
    let welcome = WelcomeModel(devices: SilentDevices(), keyReady: { false }, defaults: defaults)
    welcome.next()
    expectEq(welcome.flow.step, .hello, "name: la pagina de nombre es hello")
    return WelcomeView(welcome: welcome, chat: chat())
}

private struct Shot {
    let frames: [WelcomeFrameRole: CGRect]
    let rep: NSBitmapImageRep
    let size: CGSize

    /// Raw channel bytes at a point; bitmapData read once instead of colorAt per pixel.
    func pixel(x: CGFloat, y: CGFloat) -> [UInt8] {
        let scale = CGFloat(rep.pixelsWide) / size.width
        let px = Int(x * scale), py = Int(y * scale)
        guard let data = rep.bitmapData, px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh
        else { return [] }
        let at = py * rep.bytesPerRow + px * rep.samplesPerPixel
        return (0..<min(3, rep.samplesPerPixel)).map { data[at + $0] }
    }
}

@MainActor private func shoot(size: CGSize, dark: Bool) -> Shot? {
    let frames = Frames()
    let view = helloView()
        .onPreferenceChange(WelcomeFrames.self) { frames.value = $0 }
        .frame(width: size.width, height: size.height)
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    host.layoutSubtreeIfNeeded()
    return Shot(frames: frames.value, rep: rep, size: size)
}

/// Largest per-channel distance, 0...255; a tolerance beats raw inequality.
private func channelGap(_ a: [UInt8], _ b: [UInt8]) -> Int {
    guard !a.isEmpty, a.count == b.count else { return 0 }
    return zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
}

private func margins(_ frame: CGRect, in size: CGSize) -> (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
    (frame.minX, frame.minY, size.width - frame.maxX, size.height - frame.maxY)
}

private func save(_ shot: Shot, name: String) {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_GAP6_PNGS"],
          let png = shot.rep.representation(using: .png, properties: [:]) else { return }
    let url = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? png.write(to: url.appendingPathComponent(name + ".png"))
}

@MainActor func testTheLayoutAtTheMinimumWindow() async {
    let size = WindowChrome.contentMinSize
    for language in [AppLanguage.es, .en] {
        // Light only: the welcome forces a light scheme on this step.
        do {
            await Localized.scoped(to: language) {
                let tag = "\(language.rawValue)-light"
                guard let shot = shoot(size: size, dark: false) else { expect(false, "name \(tag): no render"); return }
                guard let field = shot.frames[.nameField], let button = shot.frames[.continueButton],
                      let heading = shot.frames[.heading]
                else { expect(false, "name \(tag): faltan frames \(shot.frames.keys)"); return }
                let m = margins(field, in: size)
                expect(m.left > 0 && m.top > 0 && m.right > 0 && m.bottom > 0, "name \(tag): el campo cabe entero \(m)")
                expect(m.left >= Stroke.ring && m.right >= Stroke.ring, "name \(tag): el halo de 3 no se recorta a los lados")
                expectEq(field.height, 50, "name \(tag): el campo mide 50")
                expectEq(field.width, min(340, size.width - 64), "name \(tag): ancho = min(340, w - 64)")
                let b = margins(button, in: size)
                expect(b.left > 0 && b.top > 0 && b.right > 0, "name \(tag): el boton cabe \(b)")
                expect(b.bottom >= Space.x4, "name \(tag): el boton no se recorta abajo (\(b.bottom))")
                expect(button.minY - field.maxY > 0, "name \(tag): el campo no pisa el boton")
                expect(heading.maxY <= field.minY, "name \(tag): titulo y texto terminan sobre el campo")
                // Inside the fill, left padding (clear of border and text), against the
                // page at the same y just outside the field.
                let inside = shot.pixel(x: field.minX + ControlMetrics.nameFieldInset / 2, y: field.midY)
                let outside = shot.pixel(x: field.minX - Space.x4, y: field.midY)
                expect(channelGap(inside, outside) > 8, "name \(tag): el relleno del campo se distingue de la pagina")
                expect(m.top >= Space.x4 && heading.minY > 0, "name \(tag): arriba no se recorta (\(m.top))")
                save(shot, name: "name-hello-\(tag)")
            }
        }
    }
}

@MainActor func testTheFormStaysCappedAndCenteredOnWiderWindows() async {
    for width in [CGFloat(1200), 1400] {
        let size = CGSize(width: width, height: 760)
        guard let shot = shoot(size: size, dark: false), let field = shot.frames[.nameField] else {
            expect(false, "name \(width): sin frame"); continue
        }
        expectEq(field.width, min(340, width - 64), "name \(width): ancho del campo")
        expect(abs(field.midX - width / 2) <= 1, "name \(width): centrado en w/2 (\(field.midX))")
    }
    // Synthetic: the window minimum is 880, so 380 only exercises the cap's lower branch.
    let narrow = CGSize(width: 380, height: 760)
    if let shot = shoot(size: narrow, dark: false), let field = shot.frames[.nameField] {
        expectEq(field.width, narrow.width - 64, "name 380: sigue a la ventana menos 64")
        expect(abs(field.midX - narrow.width / 2) <= 1, "name 380: centrado")
    } else { expect(false, "name 380: sin frame") }
}
