import CompanionCore
import CompanionTestKit
import AppKit
import SwiftUI
import Testing
@testable import CompanionUI

// Gap 5 (WIN-10): the permissions page is two columns. Which group the guide
// shows, how each group reads and how the art moves are pure decisions, so
// they are checked here without rendering a window.

private let order = WelcomePermission.allCases

@Test @MainActor func permissionGuideActiveIsTheFirstNotGranted() {
    expectEq(PermissionGuide.active(granted: [], acting: nil), .microphone, "permissionGuide: none granted")
    expectEq(PermissionGuide.active(granted: [.microphone], acting: nil), .accessibility,
             "permissionGuide: some granted")
    expectEq(PermissionGuide.active(granted: [.accessibility], acting: nil), .microphone,
             "permissionGuide: a gap before a granted one still comes first")
    expectEq(PermissionGuide.active(granted: [.microphone, .accessibility, .speechRecognition], acting: nil),
             .screenRecording, "permissionGuide: order is the declared one, not the granted one")
}

@Test @MainActor func permissionGuideActiveWhenEverythingIsGrantedIsNone() {
    expectEq(PermissionGuide.active(granted: Set(order), acting: nil), nil,
             "permissionGuide: all granted has no active group, as the reference's complete state")
    expectEq(PermissionGuide.active(granted: Set(order), acting: .screenRecording), nil,
             "permissionGuide: a stale acting does not resurrect a granted group")
}

@Test @MainActor func permissionGuideActiveFollowsWhatTheUserIsActingOn() {
    expectEq(PermissionGuide.active(granted: [], acting: .screenRecording), .screenRecording,
             "permissionGuide: acting wins over the first pending")
    expectEq(PermissionGuide.active(granted: [.microphone], acting: .speechRecognition), .speechRecognition,
             "permissionGuide: acting on a later group")
}

@Test @MainActor func permissionGuideActiveHonoursACustomOrder() {
    expectEq(PermissionGuide.active(granted: [], acting: nil, order: [.screenRecording, .microphone]),
             .screenRecording, "permissionGuide: order is a parameter")
    expectEq(PermissionGuide.active(granted: [], acting: nil, order: []), nil, "permissionGuide: empty order")
}

@Test @MainActor func permissionGuideStateOfEachGroup() {
    let granted: Set<WelcomePermission> = [.microphone]
    expectEq(PermissionGuide.state(of: .microphone, granted: granted, active: .accessibility), .granted,
             "permissionGuide: granted group")
    expectEq(PermissionGuide.state(of: .accessibility, granted: granted, active: .accessibility), .active,
             "permissionGuide: the active group")
    expectEq(PermissionGuide.state(of: .screenRecording, granted: granted, active: .accessibility), .upcoming,
             "permissionGuide: a later group")
    expectEq(PermissionGuide.state(of: .microphone, granted: [], active: .microphone), .active,
             "permissionGuide: active is not granted yet")
}

@Test @MainActor func permissionGuideStepNumbersCountFromOne() {
    expectEq(PermissionGuide.number(of: .microphone), 1, "permissionGuide: first step is 1")
    expectEq(PermissionGuide.number(of: .speechRecognition), order.count, "permissionGuide: last step")
}

@Test @MainActor func permissionGuideSizeIsTheSmallerSideOfItsColumn() {
    let floor = PermissionGuide.minimumSize
    let wide = floor * 3
    let short = floor * 2
    expectEq(PermissionGuide.guideSize(columnWidth: wide, availableHeight: short), short,
             "permissionGuide: a wide, short column is bound by its height")
    expectEq(PermissionGuide.guideSize(columnWidth: short, availableHeight: wide), short,
             "permissionGuide: a narrow, tall column is bound by its width")
    expectEq(PermissionGuide.guideSize(columnWidth: short, availableHeight: short), short,
             "permissionGuide: equal sides")
}

@Test @MainActor func permissionGuideSizeKeepsItsFloorOnNarrowColumnsOnly() {
    let floor = PermissionGuide.minimumSize
    expect(floor > 0, "permissionGuide: the floor is a real size")
    expectEq(PermissionGuide.guideSize(columnWidth: 0, availableHeight: floor * 2), floor,
             "permissionGuide: a collapsed width still draws the floor")
    expectEq(PermissionGuide.guideSize(columnWidth: floor / 2, availableHeight: floor * 2), floor,
             "permissionGuide: a narrow column keeps the floor")
    expectEq(PermissionGuide.guideSize(columnWidth: floor * 2, availableHeight: .infinity), floor * 2,
             "permissionGuide: an unbounded height leaves the width in charge")
}

@Test @MainActor func permissionGuideSizeFitsTheHeightEvenBelowTheFloor() {
    let floor = PermissionGuide.minimumSize
    expectEq(PermissionGuide.guideSize(columnWidth: floor * 2, availableHeight: floor / 2), floor / 2,
             "permissionGuide: a short window wins over the floor, the guide never overflows")
    expectEq(PermissionGuide.guideSize(columnWidth: floor * 2, availableHeight: 0), 0, "permissionGuide: zero height")
    expectEq(PermissionGuide.guideSize(columnWidth: -5, availableHeight: -5), 0, "permissionGuide: never negative")
    expectEq(PermissionGuide.guideSize(columnWidth: .nan, availableHeight: .nan), 0, "permissionGuide: not finite")
}

@Test @MainActor func permissionGuideActingIsKeptUntilItsOwnPermissionIsGranted() {
    expectEq(PermissionGuide.acting(afterFinishing: .microphone, current: .microphone, granted: []), .microphone,
             "permissionGuide: a denied request keeps the guide on it")
    expectEq(PermissionGuide.acting(afterFinishing: .microphone, current: .microphone, granted: [.microphone]), nil,
             "permissionGuide: a granted one clears it")
    expectEq(PermissionGuide.acting(afterFinishing: .microphone, current: .accessibility, granted: [.microphone]),
             .accessibility, "permissionGuide: A then B, A finishing keeps B")
    expectEq(PermissionGuide.acting(afterFinishing: .microphone, current: .accessibility, granted: []),
             .accessibility, "permissionGuide: A denied does not touch B")
    expectEq(PermissionGuide.acting(afterFinishing: .microphone, current: nil, granted: [.microphone]), nil,
             "permissionGuide: nothing to clear")
}

@Test @MainActor func permissionGuideActiveCoversTheEdges() {
    expectEq(PermissionGuide.active(granted: [.microphone], acting: .microphone), .accessibility,
             "permissionGuide: acting on a just-granted one moves on")
    expectEq(PermissionGuide.active(granted: [.microphone, .accessibility, .screenRecording], acting: .speechRecognition),
             .speechRecognition, "permissionGuide: acting on the last one before it is granted")
    expectEq(PermissionGuide.active(granted: Set(order), acting: .speechRecognition), nil,
             "permissionGuide: the last one granted completes the page")
    expectEq(PermissionGuide.active(granted: [.accessibility, .screenRecording, .speechRecognition], acting: .accessibility),
             .microphone, "permissionGuide: revoked mid-flow, acting on a granted one, the first gap leads")
    expectEq(PermissionGuide.active(granted: [.accessibility, .screenRecording, .speechRecognition], acting: nil),
             .microphone, "permissionGuide: revoked mid-flow, no acting")
}

@Test @MainActor func permissionGuideStateWhenNothingIsActive() {
    for permission in WelcomePermission.allCases {
        expectEq(PermissionGuide.state(of: permission, granted: Set(order), active: nil), .granted,
                 "permissionGuide: \(permission) is granted when the page is complete")
        expectEq(PermissionGuide.state(of: permission, granted: [], active: nil), .upcoming,
                 "permissionGuide: \(permission) is upcoming when nothing is granted or active")
    }
}

@Test @MainActor func permissionGuideBouncesOnlyOnARealGrant() {
    expect(PermissionGuide.bounces(from: .upcoming, to: .granted, reduceMotion: false), "upcoming to granted")
    expect(PermissionGuide.bounces(from: .active, to: .granted, reduceMotion: false), "active to granted")
    expect(!PermissionGuide.bounces(from: .granted, to: .granted, reduceMotion: false), "granted to granted")
    expect(!PermissionGuide.bounces(from: .granted, to: .upcoming, reduceMotion: false), "a revoke does not pop")
    expect(!PermissionGuide.bounces(from: .upcoming, to: .active, reduceMotion: false), "becoming active")
    expect(!PermissionGuide.bounces(from: .upcoming, to: .granted, reduceMotion: true), "reduce motion: no bounce")
}

@Test @MainActor func permissionGuideBounceFollowsTheOvershootCurve() {
    let samples = PermissionGuide.bounceScales(count: 12)
    expectEq(samples.count, 12, "permissionGuide: as many samples as asked")
    expectEq(samples.first, PermissionGuide.stepStartScale, "permissionGuide: starts small")
    expectEq(samples.last, 1, "permissionGuide: settles at full size")
    expect(samples.contains { $0 > 1 }, "permissionGuide: overshoots, as the bounce curve does")
}

@Test @MainActor func permissionGuideBadgeIsLabelledInBothLanguages() async {
    var labels: [AppLanguage: [String]] = [:]
    for language in [AppLanguage.es, .en] {
        labels[language] = await Localized.scoped(to: language) {
            let step = PermissionGuide.stepLabel(number: 2)
            expect(step.contains("2") && step.contains(String(order.count)), "\(language): says which of how many")
            return [step] + PermissionGuide.GroupState.allCases.map { PermissionGuide.stateLabel($0) }
        }
        for text in labels[language] ?? [] { expect(!text.isEmpty && !text.hasPrefix("welcome."), "\(language): \(text)") }
    }
    expect(labels[.es] != labels[.en], "permissionGuide: es and en differ")
    expectEq(Set(labels[.en] ?? []).count, 4, "permissionGuide: each state reads differently")
}

@Test @MainActor func permissionGuideReduceMotionSkipsTheLanding() {
    expectEq(PermissionGuide.landOffset(landed: false, reduceMotion: true), 0,
             "permissionGuide: no landing, the frame is in place")
    expectEq(PermissionGuide.landOffset(landed: false, reduceMotion: false), PermissionGuide.landStartOffset,
             "permissionGuide: it starts above its place")
    expectEq(PermissionGuide.landOffset(landed: true, reduceMotion: false), 0, "permissionGuide: landed")
}

@Test @MainActor func permissionGuideAsideShowsTheActiveKind() {
    for kind in WelcomePermission.allCases {
        expectEq(PermissionGuide.content(for: kind), .art(kind), "permissionGuide: aside draws \(kind)")
    }
    expectEq(PermissionGuide.content(for: nil), .complete, "permissionGuide: nothing active is the done state")
}

@Test @MainActor func permissionGuideReferenceTimings() {
    expectEq(MotionTime.permissionFade, 0.3, "fr-permission-fade .3s")
    expectEq(MotionTime.land, 0.46, "fr-land .46s")
    expectEq(MotionTime.stepGranted, 0.36, "fr-perm-granted .36s")
    expectEq(MotionTime.permissionFade, MotionTime.panel, "the fade reuses the panel step")
}

@Test @MainActor func permissionGuideMotionIsInstantWithReduceMotion() {
    expect(PermissionGuide.swapAnimation(reduceMotion: true) == nil, "permissionGuide: swap is instant")
    expect(PermissionGuide.landAnimation(reduceMotion: true) == nil, "permissionGuide: no landing")
    expect(PermissionGuide.swapAnimation(reduceMotion: false)
           == MotionCurve.animation(MotionCurve.standard, MotionTime.permissionFade),
           "permissionGuide: swap fades on the standard curve")
    expect(PermissionGuide.landAnimation(reduceMotion: false)
           == MotionCurve.animation(MotionCurve.bounce, MotionTime.land),
           "permissionGuide: landing is the overshoot curve")
}

@Test @MainActor func permissionGuideCopyExistsInBothLanguages() async {
    var texts: [AppLanguage: String] = [:]
    for language in [AppLanguage.es, .en] {
        texts[language] = await Localized.scoped(to: language) {
            let text = PermissionGuide.completeLabel
            expect(!text.isEmpty && text != "welcome.guide.complete", "\(language): the done label is real copy")
            return text
        }
    }
    expect(texts[.es] != texts[.en], "permissionGuide: es and en say different things")
}

// Resuming onto the page: facts.granted starts empty and the first refresh()
// fills it. That hydration is the machine's state arriving, not a grant, so
// nothing pops and nothing is drawn from the empty placeholder.

private final class SwitchableDevices: WelcomeDevices, @unchecked Sendable {
    private let lock = NSLock()
    private var grants: Set<WelcomePermission>
    init(_ grants: Set<WelcomePermission>) { self.grants = grants }
    func grant(_ permission: WelcomePermission) { lock.withLock { _ = grants.insert(permission) } }
    func revoke(_ permission: WelcomePermission) { lock.withLock { _ = grants.remove(permission) } }
    func granted(_ permission: WelcomePermission) async -> Bool { lock.withLock { grants.contains(permission) } }
    func request(_ permission: WelcomePermission) async -> Bool { lock.withLock { grants.contains(permission) } }
    func verifyScreenCapture() async -> Bool { true }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
}

@MainActor private func states(_ welcome: WelcomeModel) -> [WelcomePermission: PermissionGuide.GroupState]? {
    PermissionGuide.states(granted: welcome.facts.granted, acting: nil, hydrated: welcome.hasRefreshed)
}

@MainActor private func freshModel(_ devices: SwitchableDevices) throws -> WelcomeModel {
    let defaults = try #require(UserDefaults(suiteName: "gap5-" + UUID().uuidString))
    return WelcomeModel(devices: devices, keyReady: { true }, defaults: defaults)
}

@Test @MainActor func permissionGuideDrawsNothingBeforeHydration() async throws {
    let welcome = try freshModel(SwitchableDevices([.microphone, .accessibility]))
    expect(!welcome.hasRefreshed, "permissionGuide: a fresh model has not read the machine yet")
    expect(states(welcome) == nil, "permissionGuide: no states before hydration")
    let blank = try await snapshot(welcome, language: .en, size: WindowChrome.contentMinSize)
    expectEq(blank.distinctColours, 1, "permissionGuide: the page is blank before hydration")

    await welcome.refresh()
    expect(welcome.hasRefreshed, "permissionGuide: the first refresh hydrates")
    expectEq(states(welcome)?[.microphone], .granted, "permissionGuide: hydrated, granted as the machine says")
    expectEq(states(welcome)?[.screenRecording], .active, "permissionGuide: hydrated, the first gap leads")
    let drawn = try await snapshot(welcome, language: .en, size: WindowChrome.contentMinSize)
    expect(drawn.distinctColours > 8, "permissionGuide: the page draws once hydrated")
}

@Test @MainActor func permissionGuideSeesARealGrantAfterHydration() async throws {
    let devices = SwitchableDevices([.microphone, .accessibility])
    let welcome = try freshModel(devices)
    await welcome.refresh()
    let hydrated = states(welcome)
    devices.grant(.screenRecording)
    await welcome.refresh()
    let later = states(welcome)
    expectEq(hydrated?[.screenRecording], .active, "before: screen recording leads")
    expectEq(later?[.screenRecording], .granted, "after: it is granted")
    expect(PermissionGuide.bounces(
        from: hydrated?[.screenRecording] ?? .upcoming, to: later?[.screenRecording] ?? .upcoming,
        reduceMotion: false), "permissionGuide: that real grant bounces")
    expect(!PermissionGuide.bounces(
        from: hydrated?[.microphone] ?? .upcoming, to: later?[.microphone] ?? .upcoming, reduceMotion: false),
        "permissionGuide: an already granted one does not")
}

@Test @MainActor func permissionGuideRevokeThenRegrant() async throws {
    let devices = SwitchableDevices([.microphone, .accessibility])
    let welcome = try freshModel(devices)
    await welcome.refresh()
    let granted = states(welcome)?[.microphone] ?? .upcoming

    devices.revoke(.microphone)
    await welcome.refresh()
    let revoked = states(welcome)
    expect(revoked?[.microphone] != .granted, "permissionGuide: a revoke leaves granted")
    expectEq(revoked?[.microphone], .active, "permissionGuide: the first gap leads again")
    expect(!PermissionGuide.bounces(from: granted, to: revoked?[.microphone] ?? .upcoming, reduceMotion: false),
           "permissionGuide: a revoke does not bounce")

    devices.grant(.microphone)
    await welcome.refresh()
    let regranted = states(welcome)?[.microphone] ?? .upcoming
    expectEq(regranted, .granted, "permissionGuide: re-granted")
    expect(PermissionGuide.bounces(from: revoked?[.microphone] ?? .upcoming, to: regranted, reduceMotion: false),
           "permissionGuide: the re-grant bounces")
}

@Test @MainActor func permissionGuideAllGrantedOnFirstRefreshBouncesNothing() async throws {
    let welcome = try freshModel(SwitchableDevices(Set(WelcomePermission.allCases)))
    await welcome.refresh()
    expectEq(PermissionGuide.active(granted: welcome.facts.granted, acting: nil), nil,
             "permissionGuide: nothing is active when everything is granted")
    for (permission, state) in states(welcome) ?? [:] {
        expectEq(state, .granted, "permissionGuide: \(permission) granted on arrival")
        // A badge is only ever built from this state, so its first transition is granted to granted.
        expect(!PermissionGuide.bounces(from: state, to: state, reduceMotion: false), "\(permission): no bounce")
    }
}

@Test @MainActor func permissionGuideBounceEndpointsAreExact() {
    // MotionCurve.value returns exactly 0 and 1 at x <= 0 and x >= 1 (Motion.swift:61-62),
    // and index / (count - 1) is exactly 1 at the last sample, so == is safe.
    let samples = PermissionGuide.bounceScales(count: 7)
    expectEq(samples.first, PermissionGuide.stepStartScale, "first sample is the start scale")
    expectEq(samples.last, 1, "last sample is exactly 1")
}

// The whole page at the smallest window the app allows (WindowChrome
// contentMinSize, 880x550). The left column scrolls, so a fitting height is
// meaningless: NSHostingView reports the ideal size of a ScrollView, not what
// its content needs. The render proves instead that the page draws, that the
// states change it, and that it keeps margins inside the window. With
// COMPANION_GAP5_PNG_DIR set it also leaves the pictures to look at.

private struct Ink {
    let image: CGImage
    let scale: CGFloat
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ cg: CGImage, scale: CGFloat) {
        image = cg
        self.scale = scale
        width = cg.width
        height = cg.height
        var buffer = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        guard drew else { return nil }
        bytes = buffer
    }

    func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * width + x) * 4..<(y * width + x) * 4 + 3]) }

    /// Distinct colours in a coarse sample: a flat bitmap has one.
    var distinctColours: Int {
        var seen = Set<[UInt8]>()
        for y in stride(from: 0, to: height, by: 3) { for x in stride(from: 0, to: width, by: 3) { seen.insert(pixel(x, y)) } }
        return seen.count
    }

    func share(differingFrom other: Ink) -> Double {
        guard width == other.width, height == other.height else { return 1 }
        var differing = 0
        for i in 0..<(width * height) {
            let delta = (0..<3).reduce(0) { $0 + abs(Int(bytes[i * 4 + $1]) - Int(other.bytes[i * 4 + $1])) }
            if delta > 24 { differing += 1 }
        }
        return Double(differing) / Double(width * height)
    }

    /// Margins, in points, between the window edge and the first pixel unlike the corner colour.
    var margins: (left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        let paper = pixel(0, 0)
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixel(x, y) != paper {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return (0, 0, 0, 0) }
        return (CGFloat(minX) / scale, CGFloat(width - 1 - maxX) / scale,
                CGFloat(minY) / scale, CGFloat(height - 1 - maxY) / scale)
    }
}

@MainActor private func snapshot(_ welcome: WelcomeModel, language: AppLanguage, size: CGSize) async throws -> Ink {
    try await Localized.scoped(to: language) {
        let page = WelcomePermissions(welcome: welcome)
            .padding(.horizontal, Space.x8)
            .frame(width: size.width, height: size.height)
            .background(Semantic.background)
            .environment(\.colorScheme, .light)
        // ImageRenderer leaves a ScrollView's content blank; a hosting view draws it.
        let host = NSHostingView(rootView: page)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let cg = try #require(rep.cgImage)
        return try #require(Ink(cg, scale: CGFloat(rep.pixelsWide) / host.bounds.width))
    }
}

@MainActor private func render(
    _ permissions: Set<WelcomePermission>, language: AppLanguage, size: CGSize
) async throws -> Ink {
    let welcome = try freshModel(SwitchableDevices(permissions))
    await welcome.refresh()
    return try await snapshot(welcome, language: language, size: size)
}

@Test @MainActor func permissionGuidePageDrawsAtTheMinimumWindow() async throws {
    let size = WindowChrome.contentMinSize
    let some: Set<WelcomePermission> = [.microphone, .accessibility]
    let all = Set(WelcomePermission.allCases)
    for language in [AppLanguage.es, .en] {
        let partly = try await render(some, language: language, size: size)
        let done = try await render(all, language: language, size: size)
        for (name, ink) in [("some", partly), ("all", done)] {
            expectEq(CGFloat(ink.width) / ink.scale, size.width, "\(language) \(name): window width")
            expectEq(CGFloat(ink.height) / ink.scale, size.height, "\(language) \(name): window height")
            expect(ink.distinctColours > 8, "\(language) \(name): not a flat colour")
            let m = ink.margins
            expect(m.left > 0 && m.right > 0 && m.top > 0 && m.bottom > 0,
                   "\(language) \(name): clear of every edge (left \(m.left) right \(m.right) top \(m.top) bottom \(m.bottom))")
        }
        expect(partly.share(differingFrom: done) > 0.02, "\(language): granting everything changes the page")
        guard let dir = ProcessInfo.processInfo.environment["COMPANION_GAP5_PNG_DIR"] else { continue }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, ink) in [("some", partly), ("all", done)] {
            let rep = NSBitmapImageRep(cgImage: ink.image)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("permissions-\(language.rawValue)-\(name).png"))
        }
    }
}
