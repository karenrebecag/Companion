import CompanionCore
import SwiftUI

// How the island moves (spec 16f §2.5, §9): the shape first, the content
// after, and the notch that leans toward the pointer.
extension IslandView {
    /// Panel reveal under the shape: a fade, as Incredible's.
    var contentMove: IslandMoveModifier {
        let move = IslandMotionBudget.contentIn.resolved(reduceMotion: reduceMotion)
        return IslandMoveModifier(
            opacity: contentVisible ? 1 : 0, blur: contentVisible ? 0 : move.blur,
            offset: contentVisible ? 0 : move.offset)
    }

    /// The black shape that continues the notch. At rest it is the notch,
    /// and holding it with the mouse is holding the key.
    func silhouette(_ state: IslandState) -> some View {
        let notch = geometry.notch
        let resting = IslandMotion.rests(state.size)
        return NotchShape(width: shown.width, height: shown.height, radius: radius(notch))
            .fill(IslandInk.panel)
            // Incredible's hairline: a 12 % white edge once the island opens.
            .overlay(NotchShape(width: shown.width, height: shown.height, radius: radius(notch))
                .stroke(IslandInk.rim, lineWidth: Stroke.hairline)
                .opacity(resting ? 0 : 1))
            .shadow(color: IslandInk.shadow.opacity(
                IslandChrome.shadowOpacity(resting: resting, peeking: geometry.peeking)),
                radius: Space.x4, y: Space.x2)
            .contentShape(NotchShape(width: shown.width, height: shown.height, radius: radius(notch)))
            .gesture(resting || IslandState.acceptsPointer(size: state.size, pointerDown: pointer.isDown)
                ? holdGesture : nil)
            .accessibilityLabel(Localized.string("island.pebble"))
    }

    /// The peek keeps the notch's corners; only the open panel rounds out.
    func radius(_ notch: Notch) -> CGFloat {
        shown.height > IslandChrome.peekSize(notch: notch).height ? NotchShape.openRadius : NotchShape.restRadius
    }

    /// The resting notch leans toward the pointer and back, with its shadow.
    func peek(_ state: IslandState) {
        guard IslandMotion.rests(state.size), stage == .notch else { return }
        let notch = geometry.notch
        let target = geometry.peeking ? IslandChrome.peekSize(notch: notch)
            : CGSize(width: notch.width, height: notch.height)
        withAnimation(reduceMotion ? .expoOut(MotionTime.fast) : MotionSpring.islandPeek.animation) {
            shown = target
        }
    }

    /// Shape first, content after; closing, content first (spec 16f §2.5).
    func move(from: IslandState.Size, to: IslandState.Size) {
        motion?.cancel()
        let notch = geometry.notch
        let goal = IslandChrome.shapeSize(for: to, contentHeight: contentHeight, notch: notch)
        let beats = IslandMotion.timeline(
            from: from, to: to, reduceMotion: reduceMotion, growing: IslandMotion.grows(from: shown, to: goal))
        let reopens = IslandMotion.rests(from) != IslandMotion.rests(to)
        if !IslandPopoverToggle.survives(size: to) {
            popover = nil
            // Not waiting for the fade: the click area shrinks with the decision.
            geometry.portal = nil
            // The rich answer dies with the island's rest by the same rule.
            openAnswer = nil
            geometry.answer = nil
        }
        if reopens || IslandMotion.rests(to) {
            withAnimation(reduceMotion ? nil : IslandMotionBudget.contentOut.animation(reduceMotion: false)) {
                contentVisible = false
            }
        }
        motion = Task { @MainActor in
            var clock = 0.0
            for beat in beats {
                if beat.at > clock {
                    do { try await Task.sleep(for: .seconds(beat.at - clock)) } catch { return }
                    clock = beat.at
                }
                switch beat.event {
                case .shape(let stage):
                    let target = IslandChrome.shapeSize(for: to, contentHeight: contentHeight, notch: notch)
                    // Closing under a pointer that is still there lands on the peek.
                    let resting = stage == .notch && geometry.peeking ? IslandChrome.peekSize(notch: notch) : nil
                    withAnimation(beat.curve?.animation) {
                        shown = resting ?? IslandChrome.size(of: stage, target: target, notch: notch, from: shown)
                    }
                    self.stage = stage
                case .content:
                    guard !contentVisible else { continue }
                    withAnimation(IslandMotionBudget.contentIn.animation(reduceMotion: reduceMotion)) {
                        contentVisible = true
                    }
                }
            }
        }
    }

    var iconSwap: AnyTransition {
        let swap = IslandMotionBudget.iconSwap
        return reduceMotion ? .opacity
            : .scale(scale: swap.fromScale).combined(with: .opacity)
                .combined(with: .modifier(active: IslandMoveModifier(opacity: 1, blur: swap.blur, offset: 0),
                                          identity: IslandMoveModifier(opacity: 1, blur: 0, offset: 0)))
    }
}
