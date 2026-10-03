import CompanionCore
import SwiftUI

/// Gap 5 (WIN-10): the decisions behind the two-column permissions page, kept
/// pure so they are checked without rendering a window.
enum PermissionGuide {
    enum GroupState: Equatable, CaseIterable { case active, granted, upcoming }

    enum Content: Equatable {
        case art(WelcomePermission)
        /// Every group is granted: the guide stops teaching and says so.
        case complete
    }

    /// What the user is acting on, else the first group not granted yet. A
    /// finished page has none; the reference then shows its done picture.
    static func active(
        granted: Set<WelcomePermission>, acting: WelcomePermission?,
        order: [WelcomePermission] = WelcomePermission.allCases
    ) -> WelcomePermission? {
        if let acting, order.contains(acting), !granted.contains(acting) { return acting }
        return order.first { !granted.contains($0) }
    }

    static func state(
        of permission: WelcomePermission, granted: Set<WelcomePermission>, active: WelcomePermission?
    ) -> GroupState {
        if permission == active { return .active }
        return granted.contains(permission) ? .granted : .upcoming
    }

    /// Every group's state, or nil until the machine has been read: the
    /// empty placeholder before hydration must not draw as "nothing granted".
    static func states(
        granted: Set<WelcomePermission>, acting: WelcomePermission?, hydrated: Bool
    ) -> [WelcomePermission: GroupState]? {
        guard hydrated else { return nil }
        let current = active(granted: granted, acting: acting)
        return Dictionary(uniqueKeysWithValues: WelcomePermission.allCases.map {
            ($0, state(of: $0, granted: granted, active: current))
        })
    }

    static func number(of permission: WelcomePermission) -> Int {
        (WelcomePermission.allCases.firstIndex(of: permission) ?? 0) + 1
    }

    static func content(for active: WelcomePermission?) -> Content {
        active.map(Content.art) ?? .complete
    }

    /// A narrow column keeps a hero-sized guide instead of shrinking to a
    /// speck; the width side overflows horizontally before it gets smaller.
    static let minimumSize = Container.hero

    /// The frame is square: as wide as its column unless the column is
    /// shorter than it is wide. The floor never beats the height, so a short
    /// window gets a smaller guide rather than one that overflows vertically;
    /// the floor only holds against a narrow column. An unbounded height
    /// (infinite) leaves the width in charge.
    static func guideSize(columnWidth: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let width = columnWidth.isFinite ? max(columnWidth, 0) : 0
        let height = availableHeight.isNaN ? 0 : max(availableHeight, 0)
        return max(min(width, height), min(minimumSize, height))
    }

    /// What `acting` becomes when a request for `finished` returns. Only the
    /// permission it points at, and only once granted, clears it: a denial
    /// keeps the guide on what the user is fixing, and an earlier press
    /// finishing never clears a newer one.
    static func acting(
        afterFinishing finished: WelcomePermission, current: WelcomePermission?,
        granted: Set<WelcomePermission>
    ) -> WelcomePermission? {
        current == finished && granted.contains(finished) ? nil : current
    }

    static func stepLabel(number: Int) -> String {
        String(format: Localized.string("welcome.stepOf"), number, WelcomePermission.allCases.count)
    }

    static func stateLabel(_ state: GroupState) -> String {
        switch state {
        case .active: Localized.string("welcome.permission.state.active")
        case .granted: Localized.string("permission.granted")
        case .upcoming: Localized.string("welcome.permission.state.upcoming")
        }
    }

    static var completeLabel: String { Localized.string("welcome.guide.complete") }

    // MARK: Motion

    static func swapAnimation(reduceMotion: Bool) -> Animation? {
        ChromeMotion.animation(MotionCurve.animation(MotionCurve.standard, MotionTime.permissionFade),
                               reduceMotion: reduceMotion)
    }

    static func landAnimation(reduceMotion: Bool) -> Animation? {
        ChromeMotion.animation(MotionCurve.animation(MotionCurve.bounce, MotionTime.land),
                               reduceMotion: reduceMotion)
    }

    /// Where a step circle starts before it pops to full size.
    static let stepStartScale: CGFloat = 0.6
    /// How far above its place the guide frame starts before it lands.
    static let landStartOffset: CGFloat = -14

    /// Only a real grant pops the circle: never one already granted on
    /// arrival, and never with reduce motion.
    static func bounces(from old: GroupState, to new: GroupState, reduceMotion: Bool) -> Bool {
        !reduceMotion && old != .granted && new == .granted
    }

    /// The bounce curve sampled from its start scale to 1, so a keyframe
    /// track follows the same token curve as the CSS easing.
    static func bounceScales(count: Int) -> [CGFloat] {
        guard count > 1 else { return [1] }
        return (0..<count).map { index in
            let progress = MotionCurve.value(MotionCurve.bounce, at: Double(index) / Double(count - 1))
            return stepStartScale + (1 - stepStartScale) * CGFloat(progress)
        }
    }

    /// Reduce motion: the frame is in place at once, no landing.
    static func landOffset(landed: Bool, reduceMotion: Bool) -> CGFloat {
        landed || reduceMotion ? 0 : landStartOffset
    }
}

/// The right column: the art of the active group, swapped with a fade.
struct PermissionGuideAside: View {
    let active: WelcomePermission?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        GeometryReader { geometry in
            let size = PermissionGuide.guideSize(
                columnWidth: geometry.size.width, availableHeight: geometry.size.height)
            frame(size: size)
                .id(active)
                .transition(.opacity)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(PermissionGuide.swapAnimation(reduceMotion: reduceMotion), value: active)
        .offset(y: PermissionGuide.landOffset(landed: landed, reduceMotion: reduceMotion))
        .onAppear {
            withAnimation(PermissionGuide.landAnimation(reduceMotion: reduceMotion)) { landed = true }
        }
    }

    @ViewBuilder private func frame(size: CGFloat) -> some View {
        switch PermissionGuide.content(for: active) {
        case .art(let kind):
            PermissionGuideArt(kind: kind, size: size)
        case .complete:
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Semantic.surfaceSecondary)
                .overlay {
                    Image(systemName: "checkmark.circle.fill")
                        .font(GeistFont.uiDisplay)
                        .foregroundStyle(Semantic.success)
                }
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(Semantic.border, lineWidth: Stroke.hairline))
                .frame(width: size, height: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PermissionGuide.completeLabel)
        }
    }
}
