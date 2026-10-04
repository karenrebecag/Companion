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

    package init(welcome: WelcomeModel, chat: ChatViewModel) {
        self.welcome = welcome
        self.chat = chat
    }

    package var body: some View {
        let step = welcome.flow.step
        VStack(spacing: Space.none) {
            topBar(step)
            Spacer(minLength: Space.x6)
            column(step)
                .id(step)
            Spacer(minLength: Space.x6)
            if step != .yourTurn {
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
        .background(step == .yourTurn ? Neutral.n950.color : Semantic.background)
        .environment(\.colorScheme, step == .yourTurn ? .dark : .light)
        .animation(.springSheet, value: step)
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
        case .hello: WelcomeHello()
        case .keys: WelcomeKeys(chat: chat, keys: keys)
        case .permissions: WelcomePermissions(welcome: welcome)
        case .holdKey: WelcomeHoldKey()
        case .microphone: WelcomeMicrophone(level: welcome.level, heard: welcome.facts.micHeard)
        case .yourTurn: WelcomeYourTurn(partial: chat.session.projection.partial)
        }
    }

    /// What each screen waits on, for as long as it is on screen.
    private func watch(_ step: WelcomeStep) async {
        // Incredible runs its focus check as the step appears too: a relaunch
        // onto permissions asks again without waiting for a focus change.
        if step == .permissions { await welcome.refocused() } else { await welcome.refresh() }
        switch step {
        case .hello:
            await welcome.greet()
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
