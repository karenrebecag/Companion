import CompanionCore
import SwiftUI

// Arc's agent-run timeline in the island. One surface holds the run: a
// header whose loader folds into a check or a cross, then the steps on a
// rail that fills as the specialist works.

enum AgentRunMetrics {
    static let node: CGFloat = 22
    static let icon: CGFloat = 10
    static let track: CGFloat = 1.5
    /// Arc's step header is 40 tall; the rail's track fills what the node leaves.
    static let rowMinHeight: CGFloat = 40
    static var trackLength: CGFloat { rowMinHeight - node - Space.x1 }
    /// Arc's shimmer drifts across the active title once every 2.4 s.
    static let shimmerPeriod: TimeInterval = 2.4
    static let titleSize: CGFloat = 12.5
    static let metaSize: CGFloat = 11.5
    static let loader: CGFloat = 16
    static let arcFraction: CGFloat = 0.38
    /// The active node's arc turns once a period.
    static let arcPeriod: TimeInterval = 1.1
}

/// The run: the job as Arc's agent run, on the island's own grid. The island
/// is the surface, so the steps are rows, not a card in a card; the status
/// row above carries the run's loader, goal, step count and time. At rest the
/// newest steps show and the rest fold into one line; under the pointer or
/// with the field focused it opens to every step.
struct IslandRunCard: View {
    let job: JobTimeline
    var expanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            rows(now: context.date)
        }
    }

    private func rows(now: Date) -> some View {
        let steps = AgentRunModel.steps(steps: job.steps, now: now, language: Localized.language())
        let (folded, shown) = AgentRunModel.visible(steps, expanded: expanded)
        return VStack(alignment: .leading, spacing: Space.none) {
            if folded > 0 {
                AgentRunFold(count: folded)
                    .transition(.opacity)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, step in
                AgentRunRow(step: step, isLast: index == shown.count - 1)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(ArcMotion.panel.animation(reduceMotion: reduceMotion), value: shown.map(\.id))
        .animation(ArcMotion.panel.animation(reduceMotion: reduceMotion), value: folded)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// Older finished steps, folded into one quiet line above the newest.
private struct AgentRunFold: View {
    let count: Int

    static func text(_ count: Int) -> String {
        let key = count == 1 ? "agentrun.folded.one" : "agentrun.folded"
        return String(format: Localized.string(key), count)
    }

    var body: some View {
        IslandGridRow {
            Image(systemName: "ellipsis")
                .font(Fonts.geist(AgentRunMetrics.icon))
                .foregroundStyle(ArcTone.textMuted.color)
        } content: {
            Text(Self.text(count))
                .font(Fonts.geist(AgentRunMetrics.metaSize))
                .foregroundStyle(ArcTone.textMuted.color)
        }
        .frame(minHeight: AgentRunMetrics.rowMinHeight - Space.x2)
    }
}

private struct AgentRunRow: View {
    let step: AgentRunStep
    let isLast: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        IslandGridRow(alignment: .top) {
            rail
        } content: {
            AgentRunSwap(text: step.title)
                .font(Fonts.geist(AgentRunMetrics.titleSize).weight(step.status == .active ? .medium : .regular))
                .foregroundStyle(titleInk)
                .shimmering(active: step.status == .active && !reduceMotion, period: AgentRunMetrics.shimmerPeriod,
                            delay: 0)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minHeight: AgentRunMetrics.node)
        } trail: {
            if let duration = step.duration {
                Text(duration)
                    .font(Fonts.geist(AgentRunMetrics.metaSize).monospacedDigit())
                    .foregroundStyle(ArcTone.textMuted.color)
                    .frame(minHeight: AgentRunMetrics.node)
            }
        }
        // The last row has no track below it, so it is only as tall as its node.
        .frame(minHeight: isLast ? AgentRunMetrics.node : AgentRunMetrics.rowMinHeight, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Localized.string(AgentRunModel.stateKey(step.status)))
    }

    private var titleInk: Color {
        step.status == .done ? ArcTone.textSecondary.color : ArcTone.foreground.color
    }

    private var rail: some View {
        VStack(spacing: Space.x1) {
            AgentRunNode(step: step)
            if !isLast {
                // The track fills down from the node once the step is behind the run.
                Capsule().fill(ArcTone.border.color)
                    .overlay(alignment: .top) {
                        Capsule().fill(ArcTone.accent.color)
                            .scaleEffect(x: 1, y: step.railFill, anchor: .top)
                    }
                    .frame(width: AgentRunMetrics.track, height: AgentRunMetrics.trackLength)
                    .animation(ArcMotion.panel.animation(reduceMotion: reduceMotion), value: step.railFill)
            }
        }
        .frame(width: AgentRunMetrics.node)
        .accessibilityHidden(true)
    }
}

/// The step's tool on a ring: the active one wears a turning arc, a failed
/// one a danger ring.
private struct AgentRunNode: View {
    let step: AgentRunStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    var body: some View {
        ZStack {
            Circle().fill(ArcTone.surface.color)
            Circle().strokeBorder(ring, lineWidth: step.status == .failed ? 1.5 : 1)
            Image(systemName: step.icon)
                .font(Fonts.geist(AgentRunMetrics.icon).weight(.medium))
                .foregroundStyle(ink)
            if step.status == .active {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    let turn = timeline.date.timeIntervalSince(started) / AgentRunMetrics.arcPeriod
                    Circle()
                        .trim(from: 0, to: AgentRunMetrics.arcFraction)
                        .stroke(ArcTone.accent.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(turn.truncatingRemainder(dividingBy: 1) * 360 - 90))
                }
                .transition(.opacity)
            }
        }
        .frame(width: AgentRunMetrics.node, height: AgentRunMetrics.node)
        .animation(ArcMotion.fade(), value: step.status)
    }

    private var ring: Color {
        step.status == .failed ? ArcTone.danger.color : ArcTone.border.color
    }

    private var ink: Color {
        switch step.status {
        case .active: ArcTone.foreground.color
        case .done: ArcTone.textSecondary.color
        case .failed: ArcTone.danger.color
        }
    }
}

/// Copy keyed by its text crossfades in place: the new words rise a little
/// from a soft blur, the old ones leave faster.
struct AgentRunSwap: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .id(text)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 3)).animation(ArcMotion.enter()),
                    removal: .opacity.combined(with: .offset(y: -2)).animation(ArcMotion.exit(ArcMotion.Duration.fast))))
        }
        .animation(ArcMotion.enter(), value: text)
    }
}
