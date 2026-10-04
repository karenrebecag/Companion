import AppKit
import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// AppField's new rows and accessibility are opt-in: every caller that does
// not ask (Settings, Welcome, search) must speak exactly as before.

@Suite("app field accessibility") @MainActor struct AppFieldAccessibilityTests {
    @Test func theHintSaysInvalidFirst() async {
        await Localized.scoped(to: .en) {
            #expect(AppField.hint(description: nil, error: "Too short") == "Invalid. Too short")
            #expect(AppField.hint(description: "At least 32", error: nil) == "At least 32")
            #expect(AppField.hint(description: nil, error: nil) == "")
            #expect(AppField.hint(description: "At least 32", error: "Too short") == "Invalid. Too short",
                    "the error wins over the helper")
            #expect(AppField.hint(description: "At least 32", error: "") == "At least 32", "an empty error is none")
        }
    }

    @Test func theLabelIsNeverEmpty() async {
        await Localized.scoped(to: .en) {
            #expect(AppField.label(title: "Address", placeholder: "https://") == "Address")
            #expect(AppField.label(title: "", placeholder: "https://") == "https://")
            #expect(AppField.label(title: nil, placeholder: "Search") == "Search")
            let generic = AppField.label(title: nil, placeholder: "")
            #expect(!generic.isEmpty && !generic.hasPrefix("field."))
        }
    }

    @Test func defaultCallersKeepSwiftUIsOwnReading() {
        #expect(AppField.accessibility(messagesInHint: false, title: "Address", placeholder: "p",
                                       description: "help", error: "bad") == nil,
                "no label, no hint, error row stays its own element")
        let plain = AppField(title: "Key", placeholder: "p", text: .constant(""), error: "bad")
        #expect(plain.accessibilitySpec == nil, "the default init does not opt in")
    }

    @Test func optedInFieldsReadTitleAndHint() async {
        await Localized.scoped(to: .en) {
            let spec = AppField.accessibility(messagesInHint: true, title: "Key", placeholder: "p",
                                              description: "help", error: "bad")
            #expect(spec == FieldAccessibility(label: "Key", hint: "Invalid. bad"))
            let field = AppField(title: "Key", placeholder: "p", text: .constant(""), description: "help",
                                 messagesInHint: true)
            #expect(field.accessibilitySpec == FieldAccessibility(label: "Key", hint: "help"))
        }
    }

    @Test func invalidPrefixResolvesInBothLanguages() async {
        for language in [AppLanguage.en, .es] {
            let (raw, generic) = await Localized.scoped(to: language) {
                (Localized.string("field.invalid"), Localized.string("field.unnamed"))
            }
            #expect(raw.contains("%@"), "\(language): the error goes inside")
            #expect(!raw.hasPrefix("field.") && !generic.hasPrefix("field."), "\(language): no raw key")
            #expect(!raw.contains("\u{2014}") && !generic.contains("\u{2014}"), "\(language): no em dash")
        }
    }

    @Test func defaultFieldAndButtonStillRender() throws {
        let field = try #require(hosted(AppField(title: "Key", placeholder: "p", text: .constant("value"))))
        let erred = try #require(hosted(AppField(title: "Key", placeholder: "p", text: .constant("value"),
                                                 error: "bad")))
        #expect(field != erred, "the error still draws")
        let idle = try #require(hosted(AppButton("Save") {}))
        let busy = try #require(hosted(AppButton("Save", busy: true) {}))
        #expect(idle != busy, "busy shows the spinner")
    }
}

@MainActor private func hosted(_ view: some View) -> Data? {
    let size = CGSize(width: 320, height: 120)
    let host = NSHostingView(rootView: view.padding(Space.x4)
        .frame(width: size.width, height: size.height)
        .background(Semantic.background))
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
}
