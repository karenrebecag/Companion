import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// The sidebar lists the new modules, every placeholder page renders a
// text-only view sourced from the sidebar entry, the catalog covers the
// keys the sidebar and placeholder read, and the wire names reach the
// inspection mirror as their own identifiers.

@Test @MainActor func sidebarOrderIsTheFlatSectionsList() {
    let expected: [MainPage] = [
        .home, .apps, .browser, .knowledge, .savedTasks, .scheduled, .autopilot, .dictation
    ]
    expectEq(MainSidebar.sections.flatMap { $0.entries.map(\.page) }, expected,
             "sidebar: el orden real es la fuente de verdad y cubre los seis modulos nuevos")
}

@Test @MainActor func sidebarSectionsCoverHeadingsAndSymbols() {
    let expectedHeadings: [String?] = [nil, "sidebar.customize", "sidebar.superpowers"]
    expectEq(MainSidebar.sections.map(\.headingKey), expectedHeadings,
             "sidebar: tres secciones, el primero sin titulo")
    let expected: [MainPage: String] = [
        .home: "house",
        .apps: "square.grid.2x2",
        .browser: "globe",
        .knowledge: "book",
        .savedTasks: "cursorarrow.rays",
        .scheduled: "clock",
        .autopilot: "scope",
        .dictation: "mic",
    ]
    var byPage: [MainPage: String] = [:]
    for section in MainSidebar.sections {
        for entry in section.entries {
            byPage[entry.page] = entry.symbol
        }
    }
    expectEq(byPage.count, expected.count,
             "sidebar: una entrada por pagina y solo una")
    for (page, symbol) in expected {
        expectEq(byPage[page], symbol,
                 "sidebar: \(page) usa \(symbol)")
    }
}

@Test @MainActor func detailPaneFollowsAppsAvailability() {
    expectEq(DetailPane.detailPane(for: .apps, appsAvailable: true), .apps,
             "apps configuradas: la pagina real")
    expectEq(DetailPane.detailPane(for: .apps, appsAvailable: false), .home,
             "apps sin configurar: vuelve al home (no al placeholder vacio)")
    expectEq(DetailPane.detailPane(for: .home, appsAvailable: true), .home,
             "home siempre es home")
    expectEq(DetailPane.detailPane(for: .home, appsAvailable: false), .home,
             "home siempre es home")
    let newPages: [MainPage] = [.browser, .knowledge, .savedTasks, .scheduled, .autopilot, .dictation]
    for page in newPages {
        for available in [true, false] {
            expectEq(
                DetailPane.detailPane(for: page, appsAvailable: available),
                .placeholder(page),
                "\(page): placeholder cuando appsAvailable=\(available)"
            )
        }
    }
}

@Test @MainActor func placeholderIsBuiltFromTheSidebarEntry() {
    // Every page with a bodyKey yields a placeholder whose symbol and
    // titleKey match the sidebar entry; home and apps have no placeholder.
    for section in MainSidebar.sections {
        for entry in section.entries {
            guard let bodyKey = entry.bodyKey else {
                expect(MainSidebar.placeholder(for: entry.page) == nil,
                       "sidebar: \(entry.page) sin bodyKey no tiene placeholder")
                continue
            }
            let placeholder = MainSidebar.placeholder(for: entry.page)
            expect(placeholder != nil,
                   "sidebar: \(entry.page) con bodyKey tiene placeholder")
            expectEq(placeholder?.symbol, entry.symbol,
                     "sidebar: \(entry.page) reusa el simbolo de su fila")
            expectEq(placeholder?.titleKey, entry.titleKey,
                     "sidebar: \(entry.page) reusa la clave de titulo de su fila")
            expectEq(placeholder?.bodyKey, bodyKey,
                     "sidebar: \(entry.page) lleva la clave de cuerpo del sidebar")
        }
    }
}

// The accessibility tree of an NSHostingView outside a key window exposes no
// SwiftUI controls, so a walk over it passes whatever the page holds. The
// body's runtime type spells out every view in the hierarchy instead,
// helpers returning `some View` included, so a control anywhere in the page
// shows up in it.
private let controlTypeNames = ["Button<", "Toggle<", "TextField<", "SecureField<", "Menu<", "Picker<", "Slider<", "Stepper<", "Link<"]

@MainActor private func controlTypes<V: View>(in view: V) -> [String] {
    let tree = String(reflecting: type(of: view.body))
    return controlTypeNames.filter { tree.contains($0) }
}

@Test @MainActor func everyPlaceholderHoldsNoInteractiveControl() {
    let pages = MainSidebar.sections.flatMap(\.entries).compactMap { MainSidebar.placeholder(for: $0.page) }
    expectEq(pages.count, 6, "placeholder: los seis modulos nuevos tienen pagina")
    for placeholder in pages {
        expectEq(controlTypes(in: ModulePlaceholderPage(placeholder: placeholder)), [],
                 "placeholder: \(placeholder.page) no tiene controles que no hagan nada")
    }
}

private struct ViewWithAButton: View {
    var body: some View {
        VStack { Text(Localized.string("placeholder.notYet")); Button(Localized.string("placeholder.notYet")) {} }
    }
}

@Test @MainActor func theControlCheckSeesAButtonWhenThereIsOne() {
    expectEq(controlTypes(in: ViewWithAButton()), ["Button<"],
             "control check: un Button en el arbol aparece, si no la prueba de arriba seria vacua")
}

@Test @MainActor func moduleKeysExistInBothCatalogs() {
    var keys: Set<String> = ["placeholder.notYet"]
    for section in MainSidebar.sections {
        for entry in section.entries {
            keys.insert(entry.titleKey)
            if let bodyKey = entry.bodyKey { keys.insert(bodyKey) }
        }
    }
    for headingKey in MainSidebar.sections.map(\.headingKey).compactMap({ $0 }) {
        keys.insert(headingKey)
    }
    let en = catalog("en")
    let es = catalog("es")
    expect(!en.isEmpty && !es.isEmpty, "catalog: ambos catalogos se leyeron del bundle")
    for key in keys.sorted() {
        expect(en[key] != nil, "catalog: en tiene \(key)")
        expect(es[key] != nil, "catalog: es tiene \(key)")
        let enValue = en[key] ?? ""
        let esValue = es[key] ?? ""
        expect(!enValue.isEmpty, "catalog: en[\(key)] no esta vacio")
        expect(!esValue.isEmpty, "catalog: es[\(key)] no esta vacio")
        expect(enValue != key, "catalog: en[\(key)] no es la clave cruda")
        expect(esValue != key, "catalog: es[\(key)] no es la clave cruda")
    }
}

@Test @MainActor func wireNamesArePinnedForEveryPage() {
    let expected: [MainPage: String] = [
        .home: "home",
        .apps: "apps",
        .browser: "browser",
        .knowledge: "knowledge",
        .savedTasks: "saved_tasks",
        .scheduled: "scheduled",
        .autopilot: "autopilot",
        .dictation: "dictation",
    ]
    for (page, wire) in expected {
        expectEq(InspectionMirror.name(of: page), wire,
                 "inspeccion: \(page) sale al espejo como \(wire)")
    }
}

@Test @MainActor func pageAnimationIsNonNilUnderReduceMotion() {
    let reduceMotion = ModulePlaceholderPage.pageAnimation(reduceMotion: true)
    let normal = ModulePlaceholderPage.pageAnimation(reduceMotion: false)
    // Reduce Motion must still crossfade the page change; the value is
    // non-nil so the .animation modifier on the body actually animates.
    let expectedReduce = MotionCurve.animation(MotionCurve.linear, MotionTime.fast)
    expectEq(reduceMotion, expectedReduce,
             "reduceMotion: la curva es linear y la duracion es MotionTime.fast")
    expectEq(normal, .springSelect,
             "default: la curva es el muelle select")
}

private func catalog(_ language: String) -> [String: String] {
    guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
          let dict = NSDictionary(contentsOfFile: path + "/Localizable.strings") as? [String: String]
    else { return [:] }
    return dict
}
