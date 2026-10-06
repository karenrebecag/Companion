import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing

// S4 of the Settings brief. Sizes come from the pure table.
// local reference; brief ajustes-hoja-incredible S4.

// MARK: - Sizes and variants

@Test @MainActor func settingsDialogsSizes() {
    expectEq(SettingsDialogMetrics.popup(.normal).maxWidth, 620, "ancho normal")
    expectEq(SettingsDialogMetrics.popup(.wide).maxWidth, 780, "ancho amplio")
    expectEq(SettingsDialogMetrics.popup(.tall).maxWidth, 520, "el alto es el ancho menor")
    expectEq(SettingsDialogMetrics.popup(.tall).minHeight, 520, "tope del piso")
    expectEq(SettingsDialogMetrics.popup(.normal).minHeight, nil, "normal no impone piso")
    expectEq(SettingsDialogMetrics.popup(.wide).minHeight, nil, "amplio no impone piso")
    expectEq(SettingsDialogMetrics.minimumHeight(.tall, viewport: 2000), 520, "el piso no pasa de su tope")
    let short = SettingsDialogMetrics.minimumHeight(.tall, viewport: 500)
    expect(abs(short - 280) < 1, "en un viewport bajo el piso es la fraccion, no el tope (\(short))")
    expectEq(SettingsDialogMetrics.minimumHeight(.normal, viewport: 2000), 0, "sin piso")
    expectEq(SettingsDialogMetrics.alertCap(.purgeAttachments), 440, "tope de la alerta")
    expectEq(SettingsDialogMetrics.alertCap(.shortcuts), nil, "un popup no tiene tope de alerta")
    expectEq(SettingsDialogMetrics.width(.purgeAttachments), 440, "la alerta usa su tope")
    expectEq(SettingsDialogMetrics.width(.shortcuts), 620, "el popup usa su variante")
}

@Test @MainActor func settingsDialogsAssignsEachDialogItsKind() {
    expectEq(SettingsDialogID.shortcuts.popupWidth, .normal, "atajos")
    expectEq(SettingsDialogID.permissions.popupWidth, .normal, "permisos")
    expectEq(SettingsDialogID.purgeAttachments.popupWidth, nil, "vaciar archivos no es popup")
    expect(SettingsDialogID.purgeAttachments.isAlert, "vaciar archivos es alerta")
    expect(!SettingsDialogID.shortcuts.isAlert && !SettingsDialogID.permissions.isAlert, "los popups no son alerta")
}

@Test @MainActor func settingsDialogsOpenedByResolvesEveryIDAndRejectsStrangers() {
    for id in SettingsDialogID.allCases {
        expectEq(SettingsDialogID.opened(by: id.rawValue), id, "el id \(id.rawValue) abre su dialogo")
    }
    expectEq(SettingsDialogID.opened(by: "settings.permissions"), .permissions, "el id de la fila abre el popup")
    expectEq(SettingsDialogID.opened(by: "settings.nope"), nil, "un id desconocido no abre nada")
    expectEq(SettingsDialogID.opened(by: ""), nil, "vacio no abre nada")
}

@Test @MainActor func settingsDialogsFocusStartsOnTheSafeControl() {
    expectEq(SettingsDialogID.shortcuts.initialFocus, .close, "un popup enfoca el cierre")
    expectEq(SettingsDialogID.permissions.initialFocus, .close, "permisos enfoca el cierre")
    expectEq(SettingsDialogID.purgeAttachments.initialFocus, .cancel, "una alerta destructiva enfoca cancelar")
}

// MARK: - Layering

@Test @MainActor func settingsDialogsAlertPaintsAbovePopupUnderOneScrim() throws {
    let plan = SettingsDialogLayerPlan.make(popup: .shortcuts, alert: .purgeAttachments)
    let popup = try #require(plan.cards.first { $0.id == .shortcuts }, "el popup se dibuja")
    let alert = try #require(plan.cards.first { $0.id == .purgeAttachments }, "la alerta se dibuja")
    expect(alert.layer > popup.layer, "la alerta queda encima del popup")
    expectEq(plan.cards.count, 2, "dos tarjetas")
    let scrim = try #require(plan.scrim, "hay una capa de velo")
    expect(scrim > popup.layer && scrim < alert.layer, "un solo velo, entre el popup y la alerta")
}

@Test @MainActor func settingsDialogsPopupAloneGetsItsOwnScrimBelowIt() throws {
    let plan = SettingsDialogLayerPlan.make(popup: .permissions, alert: nil)
    let card = try #require(plan.cards.first, "el popup se dibuja")
    expectEq(plan.cards.count, 1, "una tarjeta")
    expect(try #require(plan.scrim, "velo") < card.layer, "el velo va debajo del popup")
}

@Test @MainActor func settingsDialogsAlertAloneAndNothing() throws {
    let alone = SettingsDialogLayerPlan.make(popup: nil, alert: .purgeAttachments)
    let card = try #require(alone.cards.first, "la alerta se dibuja")
    expect(try #require(alone.scrim, "velo") < card.layer, "el velo va debajo de la alerta")
    let none = SettingsDialogLayerPlan.make(popup: nil, alert: nil)
    expect(none.cards.isEmpty && none.scrim == nil, "sin dialogos no se dibuja nada")
}

// MARK: - Esc and stack

@Test @MainActor func settingsDialogsEscapeTable() {
    func target(
        approval: Bool = false, settingsOpen: Bool = true, canCloseSheet: Bool = true,
        dropdown: Bool = false, dialog: Bool = false, searchEmpty: Bool = true, voice: Bool = false
    ) -> SettingsExitTarget {
        SettingsExitChain.target(
            approval: approval, settingsOpen: settingsOpen, canCloseSheet: canCloseSheet,
            dropdown: dropdown, dialog: dialog, searchEmpty: searchEmpty, voice: voice)
    }
    expectEq(target(approval: true, dropdown: true, dialog: true, voice: true), .approval, "la aprobacion sigue primera")
    expectEq(target(dropdown: true, dialog: true), .dropdown, "el menu de la hoja sigue encima del popup")
    expectEq(target(dialog: true, searchEmpty: false), .dialog, "el dialogo gana a la busqueda y al cierre")
    expectEq(target(searchEmpty: false), .clearSearch, "sin dialogo, Esc limpia la busqueda")
    expectEq(target(), .closeSheet, "el siguiente Esc cierra la hoja")
    expectEq(target(settingsOpen: false), .none, "sin hoja ni nada abierto no hay objetivo")
    expectEq(target(settingsOpen: false, dialog: true), .none, "un dialogo con la hoja cerrada no atrapa Esc")
    expectEq(target(settingsOpen: false, dropdown: true), .dropdown, "un menu fuera de la hoja se cierra")
    expectEq(target(settingsOpen: false, voice: true), .voice, "sin hoja, Esc cuelga la voz")
    expectEq(target(canCloseSheet: false), .none, "una hoja que no puede cerrarse ignora Esc")
}

@Test @MainActor func settingsDialogsStackClosesTheAlertBeforeThePopup() {
    var stack = SettingsDialogStack()
    expect(!stack.isPresented, "vacia al inicio")
    stack.present(.shortcuts)
    stack.present(.purgeAttachments)
    expect(stack.dismissTop(), "cierra la alerta")
    expectEq(stack.popup, .shortcuts, "el popup sigue")
    expectEq(stack.alert, nil, "la alerta ya no esta")
    expect(stack.dismissTop(), "luego cierra el popup")
    expect(!stack.dismissTop(), "un tercer Esc ya no tiene dialogo")

    var sheet = SettingsSheetModel()
    _ = sheet.open(animated: false)
    sheet.dialogs.present(.permissions)
    sheet.dialogs.present(.purgeAttachments)
    expect(sheet.dismissDialog(), "el root cierra la alerta y deja la hoja")
    expect(sheet.isOpen, "la hoja sigue abierta")
    expectEq(sheet.dialogs.popup, .permissions, "el popup queda para el siguiente Esc")
    expect(sheet.dismissDialog(), "el siguiente cierra el popup")
    expectEq(sheet.escape(), .close, "recien ahi la hoja se cierra")
}

@Test @MainActor func settingsDialogsReopeningTheSheetDropsDialogs() {
    var sheet = SettingsSheetModel()
    _ = sheet.open(animated: false)
    sheet.dialogs.present(.shortcuts)
    _ = sheet.close(animated: false)
    _ = sheet.open(animated: false)
    expect(!sheet.dialogs.isPresented, "reabrir la hoja no restaura el popup")
}

// MARK: - The purge confirmation

@Test @MainActor func settingsDialogsConfirmRunsThePurgeExactlyOnce() {
    var stack = SettingsDialogStack()
    stack.present(.purgeAttachments)
    var purges = 0
    expect(stack.confirm { purges += 1 }, "confirmar con la alerta abierta actua")
    expectEq(purges, 1, "la purga corre una vez")
    expectEq(stack.alert, nil, "la alerta se cierra al confirmar")
    expect(!stack.confirm { purges += 1 }, "una segunda confirmacion no encuentra alerta")
    expectEq(purges, 1, "no se purga dos veces")
}

@Test @MainActor func settingsDialogsCancelAndEscapeNeverPurge() {
    var stack = SettingsDialogStack()
    var purges = 0
    stack.present(.purgeAttachments)
    _ = stack.dismissTop()
    expectEq(purges, 0, "cancelar o Esc no purga")
    expect(!stack.confirm { purges += 1 }, "sin alerta no hay nada que confirmar")
    stack.present(.shortcuts)
    expect(!stack.confirm { purges += 1 }, "un popup no confirma nada")
    expectEq(stack.popup, .shortcuts, "el popup sigue abierto")
    expectEq(purges, 0, "ninguna ruta sin confirmar purga")
}

@Test @MainActor func settingsDialogsPurgeCopySaysWhatThePurgeDeletes() throws {
    let root = try #require(Conformance.repoRoot(), "checkout")
    for lang in ["en", "es"] {
        let strings = try catalog(root, lang)
        let sublineKey = SettingsDialogID.purgeAttachments.sublineKey
        let copy = try #require(strings[sublineKey], "\(lang) tiene el texto de la alerta")
        let title = try #require(strings[SettingsDialogID.purgeAttachments.titleKey], "\(lang) titulo")
        let words = ["history", "historial", "conversations deleted"]
        for word in words {
            expect(!(title + copy).lowercased().contains(word), "\(lang): la alerta no promete borrar '\(word)'")
        }
    }
    expectEq(SettingsDialogID.purgeAttachments.titleKey, "settings.purge.title", "el titulo es el de la purga real")
    expectEq(SettingsDialogID.purgeAttachments.confirmKey, "settings.purge.confirm", "el boton es el de la purga real")
}

// MARK: - Localization

@Test @MainActor func settingsDialogsLocalizationCoversEveryDialogString() throws {
    let root = try #require(Conformance.repoRoot(), "checkout")
    let en = try catalog(root, "en")
    let es = try catalog(root, "es")
    var keys = ["settings.dialog.open", "settings.dialog.cancel", "settings.dialog.shortcuts.unset"]
    for id in SettingsDialogID.allCases {
        keys += [id.titleKey, id.sublineKey]
        if id.isAlert { keys.append(id.confirmKey) }
    }
    for key in keys {
        expect(en[key]?.isEmpty == false, "en \(key)")
        expect(es[key]?.isEmpty == false, "es \(key)")
    }
    expectEq(
        en[SettingsDialogID.shortcuts.sublineKey]?.lowercased().contains("not edited"), true,
        "en: los atajos dicen que no se editan aqui")
    expectEq(
        es[SettingsDialogID.shortcuts.sublineKey]?.lowercased().contains("no se editan"), true,
        "es: los atajos dicen que no se editan aqui")
}

// MARK: - Captures

@Test @MainActor func settingsDialogsCapturesLightAndDark() throws {
    let out = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }
    if let out { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
    for id in SettingsDialogID.allCases {
        let size = CGSize(width: SettingsDialogMetrics.width(id) + 80, height: 480)
        try capture(name: "s4-\(id.rawValue)", size: size, out: out) {
            SettingsDialogCard(
                id: id, permissions: samplePermissions, viewport: size.height, onClose: {}, onConfirm: {})
        }
    }
    let size = CGSize(width: 900, height: 640)
    try capture(name: "s4-alert-over-popup", size: size, out: out) {
        SettingsDialogLayer(
            stack: .constant(stackOver(popup: .shortcuts, alert: .purgeAttachments)),
            permissions: samplePermissions, onConfirm: {})
    }
}

@MainActor private var samplePermissions: [PermissionRowModel] {
    [
        PermissionRowModel(kind: .microphone, granted: true),
        PermissionRowModel(kind: .accessibility, granted: false),
    ]
}

@MainActor private func stackOver(popup: SettingsDialogID, alert: SettingsDialogID) -> SettingsDialogStack {
    var stack = SettingsDialogStack()
    stack.present(popup)
    stack.present(alert)
    return stack
}

private func catalog(_ root: URL, _ lang: String) throws -> [String: String] {
    let url = root.appendingPathComponent("Sources/CompanionUI/\(lang).lproj/Localizable.strings")
    return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(lang) catalog")
}

@MainActor
private func capture<V: View>(name: String, size: CGSize, out: URL?, _ make: () -> V) throws {
    var pngs: [ColorScheme: Data] = [:]
    for scheme in [ColorScheme.light, .dark] {
        let tag = scheme == .dark ? "dark" : "light"
        let png = try #require(render(make(), scheme: scheme, size: size), "\(name) \(tag) rindio")
        let rep = try #require(NSBitmapImageRep(data: png), "\(name) \(tag) es un PNG")
        expect(rep.pixelsWide >= Int(size.width) && rep.pixelsHigh >= Int(size.height),
               "\(name) \(tag): \(rep.pixelsWide)x\(rep.pixelsHigh) cubre \(size)")
        expectEq(rep.pixelsWide * Int(size.height), rep.pixelsHigh * Int(size.width), "\(name) \(tag) conserva la proporcion")
        pngs[scheme] = png
        if let out { try png.write(to: out.appendingPathComponent("\(name)-\(tag).png")) }
    }
    expect(pngs[.light] != pngs[.dark], "\(name) claro y oscuro no son el mismo bitmap")
}

@MainActor
private func render<V: View>(_ content: V, scheme: ColorScheme, size: CGSize) -> Data? {
    let view = content
        .frame(width: size.width, height: size.height)
        .background(Semantic.background)
        .environment(\.colorScheme, scheme)
        .environment(DropdownHost())
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
}
