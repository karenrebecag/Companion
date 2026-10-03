import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// The Apps catalog's first load draws Incredible 0.2.36's connectors
// skeleton (main-BL-DABKy.js, `connectors-skeleton`) instead of a spinner:
// eight cards shaped like the real ones, pulsing the way Tailwind's
// animate-pulse does, and still under Reduce Motion.

@Test @MainActor func skeletonPulseFollowsTailwindAnimatePulse() {
    #expect(SkeletonMotion.period == 2)
    #expect(SkeletonMotion.curve == [0.4, 0, 0.6, 1])
    #expect(SkeletonMotion.dimmed == 0.5)
    #expect(SkeletonMotion.opacity(elapsed: 0) == 1)
    #expect(abs(SkeletonMotion.opacity(elapsed: 1) - 0.5) < 1e-9, "50 % of the cycle is the dim keyframe")
    #expect(abs(SkeletonMotion.opacity(elapsed: 2) - 1) < 1e-9, "the cycle repeats")
    #expect(abs(SkeletonMotion.opacity(elapsed: 3) - 0.5) < 1e-9)
    // Each half is eased on its own, the way CSS applies the timing
    // function per keyframe segment.
    let quarter = 1 - 0.5 * MotionCurve.value(SkeletonMotion.curve, at: 0.5)
    #expect(abs(SkeletonMotion.opacity(elapsed: 0.5) - quarter) < 1e-9)
    let threeQuarters = 0.5 + 0.5 * MotionCurve.value(SkeletonMotion.curve, at: 0.5)
    #expect(abs(SkeletonMotion.opacity(elapsed: 1.5) - threeQuarters) < 1e-9)
}

@Test @MainActor func skeletonHoldsStillUnderReduceMotion() {
    #expect(SkeletonMotion.animates(reduceMotion: false))
    #expect(!SkeletonMotion.animates(reduceMotion: true))
    // motion-reduce:animate-none leaves the plain fill at full strength.
    for t in [0.0, 0.5, 1, 1.5] {
        #expect(SkeletonMotion.opacity(elapsed: t, reduceMotion: true) == 1)
    }
}

@Test @MainActor func appsSkeletonPinsIncrediblesConnectorCard() {
    #expect(AppsSkeletonMetrics.cards == 8)
    #expect(AppsSkeletonMetrics.columns == 2)
    #expect(AppsSkeletonMetrics.gridTop == 4, "mt-1")
    #expect(AppsSkeletonMetrics.cardPadding == 18, "the real card's p-indent, not yae's p-6")
    #expect(AppsSkeletonMetrics.cardRadius == 22, "rounded-card")
    #expect(AppsSkeletonMetrics.cardGap == 16, "gap-4")
    #expect(AppsSkeletonMetrics.icon == 48, "the real card's Na 48, not yae's 52")
    #expect(AppsSkeletonMetrics.iconRadius == 20, "rounded-xl")
    #expect(AppsSkeletonMetrics.lineRadius == 10, "rounded = --radius .625rem")
    #expect(AppsSkeletonMetrics.titleHeight == 14, "h-3.5")
    #expect(AppsSkeletonMetrics.titleWidth == 144, "w-36")
    #expect(AppsSkeletonMetrics.lineHeight == 10, "h-2.5")
    #expect(AppsSkeletonMetrics.lineWidth == 256, "w-64")
    #expect(AppsSkeletonMetrics.shortLineWidth == 160, "w-40")
    #expect(AppsSkeletonMetrics.titleToLine == 10, "mt-2.5")
    #expect(AppsSkeletonMetrics.lineToLine == 6, "mt-1.5")
}

@Test @MainActor func appsSkeletonReadsAsOneLoadingLabel() async {
    let english = await Localized.scoped(to: .en) { Localized.string("apps.loading") }
    let spanish = await Localized.scoped(to: .es) { Localized.string("apps.loading") }
    #expect(english == "Loading apps")
    #expect(spanish == "Cargando apps")
}

// The app panel keeps Incredible's spinner for its two waits (actions
// loading, disconnecting): lucide's LoaderCircle at 14 px beside a label,
// not the system's petal ProgressView.

@Test @MainActor func loaderArcIsLucidesLoaderCircleAt14() {
    #expect(LoaderArcMetrics.size == 14)
    #expect(abs(LoaderArcMetrics.lineWidth - 14.0 * 2 / 24) < 1e-9, "stroke 2 on a 24 viewBox")
    #expect(abs(LoaderArcMetrics.diameter - 14.0 * 18 / 24) < 1e-9, "radius 9 on a 24 viewBox")
    #expect(LoaderArcMetrics.sweep == 0.8, "the path leaves a 72 degree gap")
    #expect(LoaderArcMotion.period == 1, "animate-spin: 1s linear")
    #expect(LoaderArcMotion.degrees(elapsed: 0) == 0)
    #expect(abs(LoaderArcMotion.degrees(elapsed: 0.25) - 90) < 1e-9)
    #expect(abs(LoaderArcMotion.degrees(elapsed: 1.5) - 180) < 1e-9)
}

@Test @MainActor func appPanelWaitsReadLikeIncredible() async {
    #expect(AppPanelMetrics.loadingGap == 8, "gap-2")
    #expect(AppPanelMetrics.disconnectingGap == 6, "gap-1.5")
    let english = await Localized.scoped(to: .en) {
        [Localized.string("apps.panel.loading"), Localized.string("apps.panel.disconnecting")]
    }
    let spanish = await Localized.scoped(to: .es) {
        [Localized.string("apps.panel.loading"), Localized.string("apps.panel.disconnecting")]
    }
    #expect(english == ["Loading…", "Disconnecting…"])
    #expect(spanish == ["Cargando…", "Desconectando…"])
}
