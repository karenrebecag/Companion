import AppKit
import CompanionCore
import SwiftUI

/// Incredible's welcome (Wave 16c): a stepper, one idea per screen, one black
/// pill at the bottom. Always light and black-and-white: clean paper before
/// the app's own colour enters (Karen, 2026-08-26).
package struct WelcomeView: View {
    var welcome: WelcomeModel
    @Bindable var chat: ChatViewModel
    @State private var keys = KeysSettingsModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lets the gated snapshot test render the aside while the shipped flag
    /// is off; production callers leave it nil.
    var testimonialsOverride: Bool?

    package init(welcome: WelcomeModel, chat: ChatViewModel) {
        self.welcome = welcome
        self.chat = chat
    }

    init(welcome: WelcomeModel, chat: ChatViewModel, testimonialsOverride: Bool?) {
        self.init(welcome: welcome, chat: chat)
        self.testimonialsOverride = testimonialsOverride
    }

    package var body: some View {
        let step = welcome.flow.step
        // The sound check dims the screen as the last one does: Incredible
        // draws its card over the dusk, white on dark.
        let dimmed = step == .yourTurn || (step == .hello && welcome.soundCheck.holdsGreeting)
        // Only the keys step can show the aside; every other step keeps the
        // plain column, so a GeometryReader never alters its measured layout.
        let asideEnabled = step == .keys && (testimonialsOverride ?? TestimonialCarousel.enabled)
        Group {
            if asideEnabled {
                GeometryReader { proxy in
                    let wide = TestimonialCarousel.showsAside(step: step, width: proxy.size.width, enabled: true)
                    HStack(spacing: Space.none) {
                        content(step, dimmed: dimmed)
                            .frame(width: wide ? proxy.size.width * TestimonialCarousel.formShare : nil)
                        if wide {
                            // Incredible's aside keeps a 12 pt margin on three sides; the form column is its fourth.
                            WelcomeTestimonialsAside()
                                .padding([.top, .trailing, .bottom], Space.x3)
                        }
                    }
                }
            } else {
                content(step, dimmed: dimmed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dimmed ? Neutral.n950.color : Semantic.background)
        .environment(\.colorScheme, dimmed ? .dark : .light)
        .animation(.springSheet, value: step)
        .animation(
            Self.soundCardTiming(reduceMotion: reduceMotion).map { MotionCurve.animation(MotionCurve.standard, $0.enter) },
            value: dimmed)
        .task(id: step) { await watch(step) }
        // Coming back from System Settings is when a Screen Recording switch
        // flipped there can be verified (Incredible's focus listener).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await welcome.refocused() }
        }
        .onChange(of: chat.session.projection.kind) { _, kind in
            welcome.observe(kind)
            if welcome.canContinue, step == .yourTurn { welcome.next() }
        }
        .onAppear {
            welcome.resumeKeys()
            keys.secrets = chat.secrets
            keys.refresh()
        }
        .overlay(alignment: .top) {
            WelcomeSignalBurst(trigger: welcome.bursts)
                .environment(\.colorScheme, step == .yourTurn ? .dark : .light)
        }
        .overlay(alignment: .bottomTrailing) {
            if welcome.musicAvailable {
                WelcomeMusicToggle(playing: !welcome.musicMuted) { welcome.toggleMusic() }
                    .padding(Space.x7)
            }
        }
        .task(id: welcome.musicPlaying) { await welcome.syncMusic() }
        .background(WindowVisibilityReader { welcome.setWindowShown($0) })
        // The task above is cancelled with the view, so the stop is sent here.
        .onDisappear {
            welcome.setWindowShown(false)
            Task { await welcome.syncMusic() }
        }
    }

    private func content(_ step: WelcomeStep, dimmed: Bool) -> some View {
        VStack(spacing: Space.none) {
            topBar(step)
            Spacer(minLength: Space.x6)
            column(step)
                .id(step)
            Spacer(minLength: Space.x6)
            if !dimmed, step != .hello || welcome.soundCheck.showsHello {
                AppButton(
                    Localized.string(step == .cover ? "welcome.start" : "welcome.continue"),
                    kind: .neutral, shape: .pill, fullWidth: true,
                    enabled: welcome.canContinue
                ) { welcome.next() }
                .frame(maxWidth: Container.sheet)
                // Test seam for the layout tests; inert in production.
                .reportsFrame(.continueButton)
                .padding(.horizontal, Space.x8)
                .padding(.bottom, Space.x8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func topBar(_ step: WelcomeStep) -> some View {
        HStack {
            if step != .cover {
                Button { welcome.back() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Semantic.mutedForeground)
                    .accessibilityLabel(Localized.string("welcome.back"))
            }
            Spacer()
            WelcomeStepper(step: step)
            Spacer()
            if step.skippable {
                Button(Localized.string("welcome.skip")) { welcome.skip() }
                    .buttonStyle(.plain)
                    .font(GeistFont.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .frame(height: Space.x8)
        .padding(.horizontal, Space.x6)
        .padding(.top, Space.x6)
    }

    /// Permissions is two columns, so it reads at the content width; every
    /// other page keeps the narrow sheet column.
    @ViewBuilder
    private func column(_ step: WelcomeStep) -> some View {
        if step == .permissions {
            screen(step)
                .padding(.horizontal, Space.x8)
                .frame(maxWidth: Container.content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else {
            SheetColumn {
                screen(step)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func screen(_ step: WelcomeStep) -> some View {
        switch step {
        case .cover: WelcomeCover()
        case .hello:
            switch welcome.soundCheck {
            case .showing(let volume):
                WelcomeSoundCheck(welcome: welcome, volume: volume)
                    .transition(soundCardTransition)
            case .passed: WelcomeHello()
            case .unchecked: Color.clear
            }
        case .keys: WelcomeKeys(chat: chat, keys: keys)
        case .permissions: WelcomePermissions(welcome: welcome)
        case .holdKey: WelcomeHoldKey()
        case .microphone: WelcomeMicrophone(level: welcome.level, heard: welcome.facts.micHeard)
        case .yourTurn: WelcomeYourTurn(partial: chat.session.projection.partial)
        }
    }

    /// fr-sound-in (.4s up 14 px) and fr-sound-out (.6s up 6 px, blurred):
    /// styles-CTdsYdwA.css @3619-4005. Reduce Motion swaps it at once.
    static func soundCardTiming(reduceMotion: Bool) -> (enter: Double, exit: Double)? {
        reduceMotion ? nil : (0.4, MotionTime.enter)
    }

    private var soundCardTransition: AnyTransition {
        guard let timing = Self.soundCardTiming(reduceMotion: reduceMotion) else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: Space.x3_5))
                .animation(MotionCurve.animation(MotionCurve.standard, timing.enter)),
            removal: .opacity.combined(with: .offset(y: -Space.x1_5))
                .combined(with: .modifier(active: SoundCardBlur(radius: Space.x1), identity: SoundCardBlur(radius: 0)))
                .animation(MotionCurve.animation(MotionCurve.standard, timing.exit)))
    }

    /// What each screen waits on, for as long as it is on screen.
    private func watch(_ step: WelcomeStep) async {
        // Incredible runs its focus check as the step appears too: a relaunch
        // onto permissions asks again without waiting for a focus change.
        if step == .permissions { await welcome.refocused() } else { await welcome.refresh() }
        switch step {
        case .hello:
            if await welcome.holdForSoundCheck() { await welcome.greet() }
        case .permissions, .keys:
            // Rows answer a change made in System Settings without a click.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                await welcome.refresh()
            }
        case .microphone:
            await welcome.listen()
        default:
            break
        }
    }
}

/// Seven dots; the current one is a bar.
struct WelcomeStepper: View {
    let step: WelcomeStep
    private static let dot: CGFloat = 6
    private static let current: CGFloat = 18

    var body: some View {
        HStack(spacing: Space.x1) {
            ForEach(WelcomeStep.allCases, id: \.self) { each in
                Capsule()
                    .fill(each.rawValue <= step.rawValue ? Semantic.foreground : Semantic.border)
                    .frame(width: each == step ? Self.current : Self.dot, height: Self.dot)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: Localized.string("welcome.stepOf"), step.rawValue + 1, WelcomeStep.allCases.count))
    }
}

private struct SoundCardBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}
