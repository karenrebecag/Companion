import AppKit
import CompanionCore
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing
@testable import CompanionUI

// WIN-4: Incredible 0.2.36's testimonials carousel beside the signup page
// (createFirstRunIO-Dv00aAyF.js @29900-31500, interval aoe = 1e4 in
// firstRun-CdIWn2zA.js @1211631; layout in styles-CTdsYdwA.css @16428-22380).

func theCarouselWrapsAfterTheLastSlide() {
    expectEq(TestimonialCarousel.next(after: 0, count: 4), 1, "carousel: 0 -> 1")
    expectEq(TestimonialCarousel.next(after: 2, count: 4), 3, "carousel: 2 -> 3")
    expectEq(TestimonialCarousel.next(after: 3, count: 4), 0, "carousel: the last wraps to the first")
    expectEq(TestimonialCarousel.next(after: 0, count: 0), 0, "carousel: no slides stays at 0")
    expectEq(TestimonialCarousel.next(after: 0, count: 1), 0, "carousel: one slide stays on it")
}

func theCarouselAdvancesEveryTenSeconds() {
    expectEq(TestimonialCarousel.interval, .seconds(10), "carousel: aoe = 1e4")
    expectEq(TestimonialCarousel.count, 4, "carousel: 4 slides")
}

func theCarouselPausesOnEveryGuard() {
    expect(TestimonialCarousel.advances(hovering: false, focused: false, active: true, reduceMotion: false),
           "carousel: runs only when nothing pauses it")
    expect(!TestimonialCarousel.advances(hovering: true, focused: false, active: true, reduceMotion: false),
           "carousel: hover alone pauses")
    expect(!TestimonialCarousel.advances(hovering: false, focused: true, active: true, reduceMotion: false),
           "carousel: focus alone pauses")
    expect(!TestimonialCarousel.advances(hovering: false, focused: false, active: false, reduceMotion: false),
           "carousel: a hidden window alone pauses")
    expect(!TestimonialCarousel.advances(hovering: false, focused: false, active: true, reduceMotion: true),
           "carousel: Reduce Motion stops it even when otherwise running")
}

func theAsideNeedsTheFlagTheKeysStepAndRoom() {
    expect(TestimonialCarousel.showsAside(step: .keys, width: 720, enabled: true), "aside: keys at 720 enabled")
    expect(!TestimonialCarousel.showsAside(step: .keys, width: 719, enabled: true),
           "aside: hidden at 719 (@container max-width:719px)")
    expect(!TestimonialCarousel.showsAside(step: .keys, width: 1120, enabled: false), "aside: flag off hides it")
    for step in WelcomeStep.allCases where step != .keys {
        expect(!TestimonialCarousel.showsAside(step: step, width: 1120, enabled: true),
               "aside: never on \(step)")
    }
    expectEq(TestimonialCarousel.asideMinWidth, 720, "aside: threshold")
}

@MainActor func theShippedFlagStaysOffWhilePlaceholdersRemain() {
    let placeholder = [AppLanguage.es: "Aquí va una cita real de alguien que usa Companion.",
                       .en: "A real quote from someone who uses Companion goes here."]
    for language in [AppLanguage.es, .en] {
        let flag = Localized.string("welcome.testimonials.enabled", language: language)
        expectEq(flag, "0", "testimonials: shipped flag is off in \(language.rawValue)")
        if flag == "1" {
            for n in 1...TestimonialCarousel.count {
                expect(Localized.string("welcome.testimonial.\(n).quote", language: language) != placeholder[language],
                       "testimonials: enabled with placeholder quote \(n) in \(language.rawValue)")
            }
        }
    }
}

func theCarouselStateSelectsAndAdvances() {
    var state = CarouselState()
    state.select(0, count: 4)
    expectEq(state.selected, 0, "state: selecting the current dot keeps it")
    expectEq(state.restart, 1, "state: selecting the current dot restarts the timer")
    state.select(2, count: 4)
    expectEq(state.selected, 2, "state: select moves")
    expectEq(state.restart, 2, "state: select restarts")
    state.select(7, count: 4)
    expectEq(state.selected, 2, "state: out of range is ignored")
    state.select(-1, count: 4)
    expectEq(state.selected, 2, "state: negative is ignored")
    state.select(3, count: 4)
    state.advance(count: 4)
    expectEq(state.selected, 0, "state: advance wraps 3 -> 0")
    expectEq(TestimonialCarousel.next(after: 7, count: 4), 0, "carousel: pinned, 7 -> 0 (7+1 mod 4)")
    expectEq(TestimonialCarousel.next(after: -1, count: 4), 0, "carousel: pinned, -1 -> 0")
}

@MainActor func everyTestimonialIsTranslatedAndNeverIncredibles() {
    let all = WelcomeTestimonial.all
    expectEq(all.count, TestimonialCarousel.count, "testimonials: one per slide")
    for language in [AppLanguage.es, .en] {
        for n in 1...TestimonialCarousel.count {
            for part in ["quote", "ending", "name", "role"] {
                let key = "welcome.testimonial.\(n).\(part)"
                let value = Localized.string(key, language: language)
                expect(value != key && !value.isEmpty, "testimonials: \(key) translated in \(language.rawValue)")
                expect(!value.localizedCaseInsensitiveContains("incredible"),
                       "testimonials: \(key) is a placeholder, never Incredible's text")
            }
        }
    }
    expectEq(all.map(\.id), [1, 2, 3, 4], "testimonials: ids follow the key numbers")
    expect(all.allSatisfy { !$0.initials.isEmpty }, "testimonials: every portrait has initials")
    for key in ["welcome.testimonials.label", "welcome.testimonials.dot"] {
        for language in [AppLanguage.es, .en] {
            expect(Localized.string(key, language: language) != key, "carousel: \(key) in \(language.rawValue)")
        }
    }
    for language in [AppLanguage.es, .en] {
        expect(Localized.string("welcome.testimonials.dot", language: language).contains("%d"),
               "carousel: the dot label carries its number in \(language.rawValue)")
    }
}

@MainActor func initialsTakeTheFirstLettersOfTheFirstTwoWords() {
    expectEq(WelcomeTestimonial.initials(of: "Nombre de ejemplo 1"), "ND", "initials: two words")
    expectEq(WelcomeTestimonial.initials(of: "  ana  "), "A", "initials: one word")
    expectEq(WelcomeTestimonial.initials(of: ""), "", "initials: empty")
}

@Test @MainActor func welcomeTestimonialsTests() {
    theCarouselWrapsAfterTheLastSlide()
    theCarouselAdvancesEveryTenSeconds()
    theCarouselPausesOnEveryGuard()
    theAsideNeedsTheFlagTheKeysStepAndRoom()
    theShippedFlagStaysOffWhilePlaceholdersRemain()
    theCarouselStateSelectsAndAdvances()
    everyTestimonialIsTranslatedAndNeverIncredibles()
    initialsTakeTheFirstLettersOfTheFirstTwoWords()
}

// MARK: gated gallery

private final class StillDevices: WelcomeDevices, @unchecked Sendable {
    func granted(_ permission: WelcomePermission) async -> Bool { false }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { false }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func testimonialsSnapshots() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let url = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let sizes: [(String, CGSize)] = [("1120x700", CGSize(width: 1120, height: 700)),
                                     ("719x640", CGSize(width: 719, height: 640))]
    for (label, size) in sizes {
        for scheme in [ColorScheme.light, .dark] {
            let defaults = UserDefaults(suiteName: "win4-\(UUID().uuidString)") ?? .standard
            let welcome = WelcomeModel(devices: StillDevices(), keyReady: { true }, defaults: defaults)
            welcome.jump(to: .keys)
            let framed = WelcomeView(welcome: welcome, chat: chat(), testimonialsOverride: true)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: framed)
            renderer.scale = 2
            let name = "welcome-testimonials-\(label)-\(scheme == .dark ? "dark" : "light")"
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else {
                Issue.record("testimonials: \(name) could not be rendered")
                continue
            }
            try png.write(to: url.appendingPathComponent(name + ".png"))
        }
    }
}
