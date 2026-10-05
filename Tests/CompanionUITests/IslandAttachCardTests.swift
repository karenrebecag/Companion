import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import SwiftUI
import Testing

// The island card has to match the measured attachment tile, and taking one
// off has to drop it from the pending message. The stills force hover and
// focus because a test has no pointer and no key focus to borrow.
// local reference; Incredible .ci-att-card

/// A fixed red behind the tray; the samples are judged against how it reads
/// back (`backdrop`), not against its nominal channels.
private enum Backdrop {
    static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
}

@MainActor private enum CardLayout {
    static var size: CGSize {
        CGSize(width: IslandAttachMetrics.cardWidth, height: IslandAttachMetrics.cardHeight)
    }

    static let trayFrame = CGSize(width: 220, height: 160)
    static var side: CGFloat { IconButtonSize.attachmentRemove.side }

    /// The card's top-right corner in tray coordinates (origin top left): the
    /// row has no leading padding, so the card starts at x 0.
    static var corner: CGPoint {
        CGPoint(x: IslandAttachMetrics.cardWidth, y: IslandAttachMetrics.rowPaddingTop)
    }

    /// The square the disc fills when it is drawn.
    static var discSquare: CGRect {
        CGRect(x: corner.x - side / 2, y: corner.y - side / 2, width: side, height: side)
    }

    /// Inside the disc, off the glyph (its arms run on the diagonals) and past
    /// the card's right edge: only an unclipped overhang paints here.
    static var overhang: CGPoint { CGPoint(x: corner.x + 8, y: corner.y) }

    /// The same, past the card's top edge.
    static var overhangTop: CGPoint { CGPoint(x: corner.x, y: corner.y - 8) }

    /// A capture's disc stays inset by `Space.x1` inside its tile.
    static var stackDisc: CGPoint {
        CGPoint(x: IslandAttachMetrics.stackWidth - Space.x1 - side / 2,
                y: IslandAttachMetrics.rowPaddingTop + Space.x1 + side / 2)
    }

    /// Clear of every card and tile: the bare backdrop.
    static let farCorner = CGPoint(x: 210, y: 150)

    static var stripDisc: CGPoint {
        CGPoint(x: IslandAttachMetrics.stripPaddingX + IslandAttachMetrics.stackWidth - Space.x1 - side / 2,
                y: IslandAttachMetrics.stripPaddingTop + Space.x1 + side / 2)
    }
}

@Test @MainActor func islandAttachCardMetricsTable() {
    let points: [(String, CGFloat, CGFloat)] = [
        ("ancho", IslandAttachMetrics.cardWidth, 84),
        ("alto", IslandAttachMetrics.cardHeight, 102),
        ("radio", IslandAttachMetrics.cardRadius, 10),
        ("padding", IslandAttachMetrics.cardPadding, 8),
        ("nombre", IslandAttachMetrics.nameSize, 12),
        ("interlineado", IslandAttachMetrics.nameLineHeight, 16),
        ("extensión", IslandAttachMetrics.extSize, 10),
        ("extensión vertical", IslandAttachMetrics.extPaddingY, 3),
        ("extensión horizontal", IslandAttachMetrics.extPaddingX, 6),
        ("extensión radio", IslandAttachMetrics.extRadius, 5),
        ("fila gap", IslandAttachMetrics.rowGap, 8),
        ("fila arriba", IslandAttachMetrics.rowPaddingTop, 12),
        ("fila final", IslandAttachMetrics.rowPaddingTrailing, 12),
        ("quitar", IconButtonSize.attachmentRemove.side, 24),
        ("quitar desborde", IslandAttachMetrics.removeOffset, 12),
    ]
    for (name, got, want) in points {
        expectEq(got, want, "tarjeta \(name)")
    }
    expectEq(IslandAttachMetrics.cardTile, 0.06, "tarjeta: tile 6 %")
    expectEq(IslandAttachMetrics.cardBorder, 0.22, "tarjeta: borde blanco 22 %")
    expectEq(IslandAttachMetrics.extTracking, 0.04, "extensión: +0.04em")
    expectEq(IslandAttachMetrics.extFill, 0.13, "extensión: blanco 13 %")
    expectEq(IslandAttachMetrics.removeFill.hex, "141519", "quitar: disco #141519")
    expectEq(IslandAttachMetrics.removeFillAlpha, 0.9, "quitar: disco al 90 %")
    expectEq(IslandAttachMetrics.removeBorder, 0.3, "quitar: borde blanco 30 %")
    expectEq(IslandAttachMetrics.removeInkAlpha, 0.85, "quitar: tinta blanca al 85 %")
    expectEq(IslandAttachMetrics.removeHoverFill.hex, "000000", "quitar: disco negro al pasar encima")
    expectEq(IslandAttachMetrics.removeHoverFillAlpha, 0.85, "quitar: disco negro al 85 %")
    expectEq(IslandAttachMetrics.revealSeconds, 0.14, "quitar: fundido de 0.14 s")
}

@Test @MainActor func islandAttachCardHoverAndFocusReveal() {
    expect(!IslandAttachReveal.shown(cardHover: false, discHover: false, focused: false), "reposo: el × no está")
    expect(IslandAttachReveal.shown(cardHover: true, discHover: false, focused: false), "hover en la tarjeta: el × está")
    expect(IslandAttachReveal.shown(cardHover: false, discHover: true, focused: false),
           "hover solo en el disco, que desborda la tarjeta: el × se queda")
    expect(IslandAttachReveal.shown(cardHover: false, discHover: false, focused: true), "foco: el × está")
    expect(IslandAttachReveal.shown(cardHover: true, discHover: true, focused: true), "todo junto: el × está")
}

@Test @MainActor func islandRemoveStyleHidesOnlyTheCaptureDiscFromAccessibility() {
    expect(!IslandRemoveStyle.card.hidesFromAccessibility,
           "tarjeta: VoiceOver debe llegar al quitar de la tarjeta")
    expect(IslandRemoveStyle.capture.hidesFromAccessibility,
           "captura: VoiceOver quita por la acción del tile")
}

@Test @MainActor func islandAttachCardRevealFadesWithTheCssEaseInFourteenHundredths() {
    expect(IslandAttachReveal.animation(reduceMotion: true) == nil,
           "reducir movimiento: el × aparece sin animación")
    expect(IslandAttachReveal.animation(reduceMotion: false)
           == MotionCurve.animation(MotionCurve.ease, IslandAttachMetrics.revealSeconds),
           "sin reducir movimiento: el × se funde 0.14 s con ease")
}

@Test @MainActor func islandAttachCardRemoveLabelIsInBothCatalogs() async {
    let es = await Localized.scoped(to: .es) {
        String(format: Localized.string("attach.remove"), "nota.pdf")
    }
    let en = await Localized.scoped(to: .en) {
        String(format: Localized.string("attach.remove"), "nota.pdf")
    }
    expect(es.contains("nota.pdf") && en.contains("nota.pdf"), "la etiqueta nombra el archivo")
    expect(es != en, "es y en no dicen lo mismo")
    expect(es != "attach.remove" && en != "attach.remove", "la clave no se enseña")
}

@Test @MainActor func islandAttachCardClickOnTheUnseenDiscRemovesTheAttachment() throws {
    let (chat, mount) = try pendingTray()
    defer { mount.close() }
    // Only down and up, no mouseMoved: the pointer never entered the card, so
    // the disc is still unseen and has to take the click all the same.
    mount.click(at: CardLayout.corner)
    expect(chat.pendingAttachments.isEmpty, "quitar sin hover saca el adjunto del mensaje pendiente")
}

@Test @MainActor func islandAttachCardKeyFocusOnTheDiscRevealsIt() throws {
    let idle = Mount(still(tray([pdf()])), size: CardLayout.trayFrame)
    let focused = Mount(still(tray([pdf()], focusOnAppear: true)), size: CardLayout.trayFrame)
    defer {
        idle.close()
        focused.close()
    }
    let frame = CardLayout.trayFrame
    let idleRep = try #require(idle.rep())
    let bare = try backdrop(idleRep)
    expect(minRed(idleRep, in: CardLayout.discSquare, size: frame) > bare.r - 0.02,
           "sin foco ni hover: el × no está")
    let shown = poll {
        focused.rep().map { minRed($0, in: CardLayout.discSquare, size: frame) < bare.r - 0.5 } ?? false
    }
    expect(shown, "el foco del teclado en el × lo muestra")
}

@Test @MainActor func islandAttachStackDiscAtRestTakesNoClick() {
    let removed = LockedBox<[UUID]>([])
    let mount = Mount(still(tray(captures(2), onRemove: { removed.value.append($0.id) })),
                      size: CardLayout.trayFrame)
    defer { mount.close() }
    mount.click(at: CardLayout.stackDisc)
    expectEq(removed.value.count, 0, "pila en reposo: el × no recibe el clic")
}

@Test @MainActor func islandAttachStripDiscAtRestTakesNoClick() {
    let removed = LockedBox<[UUID]>([])
    let strip = IslandCaptureStrip(captures: captures(2), onRemove: { removed.value.append($0.id) }, onClose: {})
        .frame(width: CardLayout.trayFrame.width, height: CardLayout.trayFrame.height, alignment: .topLeading)
    let mount = Mount(still(strip), size: CardLayout.trayFrame)
    defer { mount.close() }
    mount.click(at: CardLayout.stripDisc)
    expectEq(removed.value.count, 0, "tira en reposo: el × no recibe el clic")
}

@Test @MainActor func islandAttachCardRenderShowsThePreview() throws {
    let photo = try solid(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    let image = Mount(still(card("foto.png", kind: .image, picture: photo)), size: CardLayout.size)
    let file = Mount(still(card("nota.pdf")), size: CardLayout.size)
    let plain = Mount(still(card("nota")), size: CardLayout.size)
    defer {
        image.close()
        file.close()
        plain.close()
    }
    let imageRep = try #require(image.rep())
    let fileRep = try #require(file.rep())
    let plainRep = try #require(plain.rep())
    let blue = bluest(imageRep)
    expect(blue.value > 0.6, "la foto está en la tarjeta — azul \(blue.value) en \(blue.x),\(blue.y)")
    let badge = CGRect(x: 8, y: CardLayout.size.height - 32, width: 44, height: 24)
    expect(mismatches(fileRep, plainRep, in: badge, size: CardLayout.size) > 8,
           "el archivo sin foto lleva la insignia de la extensión")
}

@Test @MainActor func islandAttachCardRenderShowsTheRemoveDisc() throws {
    let rest = Mount(still(tray([pdf()], pin: .rest)), size: CardLayout.trayFrame)
    let hover = Mount(still(tray([pdf()], pin: .hover)), size: CardLayout.trayFrame)
    let focus = Mount(still(tray([pdf()], pin: .focus)), size: CardLayout.trayFrame)
    defer {
        rest.close()
        hover.close()
        focus.close()
    }
    let frame = CardLayout.trayFrame
    let bare = try backdrop(try #require(rest.rep()))
    let restRed = minRed(try #require(rest.rep()), in: CardLayout.discSquare, size: frame)
    let hoverRed = minRed(try #require(hover.rep()), in: CardLayout.discSquare, size: frame)
    let focusRed = minRed(try #require(focus.rep()), in: CardLayout.discSquare, size: frame)
    expect(restRed > bare.r - 0.02, "reposo: no hay disco — rojo \(restRed)")
    expect(hoverRed < bare.r - 0.5, "hover: el disco oscuro está — rojo \(hoverRed)")
    expect(focusRed < bare.r - 0.5, "foco: el disco oscuro está — rojo \(focusRed)")
}

@Test @MainActor func islandAttachCardDiscOverhangsTheCornerUnclipped() throws {
    let mount = Mount(still(tray([pdf()], pin: .hover)), size: CardLayout.trayFrame)
    defer { mount.close() }
    let rep = try #require(mount.rep())
    let bare = try backdrop(rep)
    let right = try #require(rgb(rep, CardLayout.overhang, CardLayout.trayFrame))
    let top = try #require(rgb(rep, CardLayout.overhangTop, CardLayout.trayFrame))
    expect(right.r < bare.r - 0.5, "el disco se pinta pasado el borde derecho de la tarjeta — rojo \(right.r)")
    expect(top.r < bare.r - 0.5, "el disco se pinta sobre el borde superior de la tarjeta — rojo \(top.r)")
}

@Test @MainActor func islandAttachCardShownDiscIsTheDarkInkOverTheRedBackground() throws {
    let mount = Mount(still(tray([pdf()], pin: .hover)), size: CardLayout.trayFrame)
    defer { mount.close() }
    let rep = try #require(mount.rep())
    let color = try #require(rgb(rep, CardLayout.overhang, CardLayout.trayFrame))
    let bare = try backdrop(rep)
    // #141519 at 90 % over the backdrop, channel by channel.
    let want = (r: 0.9 * 20 / 255 + 0.1 * bare.r, g: 0.9 * 21 / 255 + 0.1 * bare.g, b: 0.9 * 25 / 255 + 0.1 * bare.b)
    expect(abs(color.r - want.r) < 0.06 && abs(color.g - want.g) < 0.06 && abs(color.b - want.b) < 0.06,
           "disco #141519 al 90 % sobre rojo — \(color), esperado \(want)")
}

@Test @MainActor func islandAttachCardDiscInkAndFillFollowTheDiscsOwnPointer() {
    expectColor(IconButton.onMediaFill(hovering: false), (20 / 255, 21 / 255, 25 / 255, 0.9),
                "disco en reposo: #141519 al 90 %")
    expectColor(IconButton.onMediaFill(hovering: true), (0, 0, 0, 0.85),
                "disco con el puntero encima: negro al 85 %")
    expectColor(IconButton.onMediaInk(hovering: false), (1, 1, 1, 0.85), "tinta en reposo: blanco al 85 %")
    expectColor(IconButton.onMediaInk(hovering: true), (1, 1, 1, 1), "tinta con el puntero encima: blanco puro")
}

@MainActor private func expectColor(
    _ color: Color, _ want: (CGFloat, CGFloat, CGFloat, CGFloat), _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let got = NSColor(color).usingColorSpace(.sRGB) else {
        expect(false, "\(label): sin espacio sRGB", sourceLocation: sourceLocation)
        return
    }
    let close = abs(got.redComponent - want.0) < 0.005 && abs(got.greenComponent - want.1) < 0.005
        && abs(got.blueComponent - want.2) < 0.005 && abs(got.alphaComponent - want.3) < 0.005
    expect(close, "\(label) — got: \(got)", sourceLocation: sourceLocation)
}

@MainActor private func still<V: View>(_ view: V) -> some View {
    view.transaction { $0.disablesAnimations = true }
}

@MainActor private func card(
    _ name: String, kind: AttachmentKind = .file, picture: CGImage? = nil
) -> some View {
    let ref = AttachmentRef(name: name, path: "/tmp/" + name, kind: kind, byteCount: 4)
    return IslandAttachCard(item: .staged(ref), picture: picture, onRemove: {})
        .background(Backdrop.red)
}

@MainActor private func tray(
    _ staged: [AttachmentRef], pin: IslandAttachRevealPin? = nil, focusOnAppear: Bool = false,
    onRemove: @escaping (AttachmentRef) -> Void = { _ in }
) -> some View {
    IslandAttachTray(staged: staged, failed: [], onRemove: onRemove, onDismissFailure: { _ in }, pin: pin,
                    focusOnAppear: focusOnAppear)
        .frame(width: CardLayout.trayFrame.width, height: CardLayout.trayFrame.height, alignment: .topLeading)
        .background(Backdrop.red)
}

/// The chat is where a real remove lands; the tray only reports which one.
@MainActor private func pendingTray() throws -> (ChatViewModel, Mount) {
    let chat = ChatViewModel(chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
                             store: MemoryConversationStore(), config: Config(),
                             attachments: MemoryAttachments())
    let ref = try #require(chat.attach(URL(fileURLWithPath: "/tmp/nota.pdf")))
    expectEq(chat.pendingAttachments.map(\.id), [ref.id], "el archivo queda en el mensaje pendiente")
    let mount = Mount(still(tray(chat.pendingAttachments, onRemove: { chat.removePending($0) })),
                      size: CardLayout.trayFrame)
    expect(poll { mount.hasKeyViews }, "la tarjeta se monta con su × en el orden del teclado")
    return (chat, mount)
}

private func pdf() -> AttachmentRef {
    AttachmentRef(name: "nota.pdf", path: "/tmp/nota.pdf", kind: .file, byteCount: 4)
}

private func captures(_ count: Int) -> [AttachmentRef] {
    (0 ..< count).map { _ in
        let name = RegionCapture.fileName(id: UUID())
        return AttachmentRef(name: name, path: "/tmp/" + name, kind: .image, byteCount: 4)
    }
}

/// Spins the run loop in short steps: a render settles on it, not on a clock.
@MainActor private func poll(timeout: TimeInterval = 2, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !done(), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return done()
}

private func solid(_ color: NSColor, side: Int = 8) throws -> CGImage {
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: side * 4, bitsPerPixel: 32))
    for y in 0 ..< side {
        for x in 0 ..< side { rep.setColor(color, atX: x, y: y) }
    }
    return try #require(rep.cgImage)
}

/// A borderless window refuses key status, and SwiftUI buttons only run for a key window.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor private final class Mount {
    let window: NSWindow
    let host: NSView
    let size: CGSize

    init(_ view: some View, size: CGSize) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .aqua)
        let window = KeyableWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(window)
        window.makeKey()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        self.window = window
        self.host = host
        self.size = size
    }

    func close() { window.orderOut(nil) }

    func rep() -> NSBitmapImageRep? {
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    /// Top-left origin, as the layout is written. Only the press and release
    /// arrive: no mouseMoved, so nothing ever hovers.
    func click(at point: CGPoint) {
        send(.leftMouseDown, at: point)
        send(.leftMouseUp, at: point)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    private func send(_ type: NSEvent.EventType, at point: CGPoint) {
        let location = NSPoint(x: point.x, y: size.height - point.y)
        guard let event = NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        else { return }
        window.sendEvent(event)
    }

    /// SwiftUI puts a proxy view in the window for each control the key can reach.
    var hasKeyViews: Bool {
        host.layoutSubtreeIfNeeded()
        return host.subviews.contains { String(describing: type(of: $0)).contains("KeyViewProxy") }
    }
}

private func channel(
    _ rep: NSBitmapImageRep, _ point: CGPoint, _ size: CGSize, _ pick: (NSColor) -> CGFloat
) -> CGFloat {
    let scaleX = CGFloat(rep.pixelsWide) / size.width
    let scaleY = CGFloat(rep.pixelsHigh) / size.height
    let x = Int((point.x * scaleX).rounded(.down))
    let y = Int((point.y * scaleY).rounded(.down))
    guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
          let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return -1 }
    return pick(color)
}

private struct Sample {
    let value: CGFloat
    let x: Int
    let y: Int
}

private func extreme(_ rep: NSBitmapImageRep, _ pick: (NSColor) -> CGFloat, _ keep: (CGFloat, CGFloat) -> Bool) -> Sample {
    var best = CGFloat(keep(0, 1) ? 2 : -1)
    var at = (0, 0)
    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let value = pick(color)
            if keep(value, best) {
                best = value
                at = (x, y)
            }
        }
    }
    return Sample(value: best, x: at.0, y: at.1)
}

private func bluest(_ rep: NSBitmapImageRep) -> Sample {
    extreme(rep, { $0.blueComponent }, { $0 > $1 })
}

private func rgb(_ rep: NSBitmapImageRep, _ point: CGPoint, _ size: CGSize) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
    let r = channel(rep, point, size) { $0.redComponent }
    guard r >= 0 else { return nil }
    return (r, channel(rep, point, size) { $0.greenComponent }, channel(rep, point, size) { $0.blueComponent })
}

/// What the red background reads as after the host's colour conversion, so
/// the samples are judged against it rather than against a pure red.
@MainActor private func backdrop(_ rep: NSBitmapImageRep) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    try #require(rgb(rep, CardLayout.farCorner, CardLayout.trayFrame))
}

@MainActor private func minRed(_ rep: NSBitmapImageRep, in rect: CGRect, size: CGSize) -> CGFloat {
    var lowest = CGFloat(2)
    for y in stride(from: rect.minY, through: rect.maxY, by: 1) {
        for x in stride(from: rect.minX, through: rect.maxX, by: 1) {
            let red = channel(rep, CGPoint(x: x, y: y), size) { $0.redComponent }
            if red >= 0 { lowest = min(lowest, red) }
        }
    }
    return lowest
}

private func mismatches(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in rect: CGRect, size: CGSize) -> Int {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 0 }
    var count = 0
    var y = rect.minY
    while y <= rect.maxY {
        var x = rect.minX
        while x <= rect.maxX {
            let left = channel(a, CGPoint(x: x, y: y), size) { $0.redComponent + $0.greenComponent + $0.blueComponent }
            let right = channel(b, CGPoint(x: x, y: y), size) { $0.redComponent + $0.greenComponent + $0.blueComponent }
            if abs(left - right) > 0.15 { count += 1 }
            x += 2
        }
        y += 2
    }
    return count
}
