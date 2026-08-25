import CompanionCore
import SwiftUI

/// The specialist at work, while it works: goal, live step and a clock. The
/// thread used to answer "is it moving?" with a pile of status lines that
/// never said which step was the current one or how long this had been going.
/// The finished report stays a normal assistant message — this card is only
/// about the wait.
struct JobCardView: View {
    /// The pedal. Nil keeps the card read-only for anywhere that shows a job
    /// it does not own.
    var onStop: (() -> Void)?
    let job: JobTimeline
    /// Only the tail: a job with forty steps must not push the conversation
    /// off screen while it runs.
    static let visibleSteps = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            header
            if job.steps.isEmpty {
                warmup
            } else {
                JobTimelineView(
                    steps: Array(job.steps.suffix(Self.visibleSteps)))
                    .padding(.leading, Space.x1)
            }
            if let summary = JobSteps.summary(job.steps, Localized.language()) {
                Text(summary)
                    .font(.uiMicro)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Semantic.surfaceOverlay))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Semantic.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var header: some View {
        HStack(spacing: Space.x2) {
            Circle()
                .fill(Semantic.accentText)
                .frame(width: IconSize.dot, height: IconSize.dot)
            Text(job.goal ?? JobCardCopy.working)
                .font(.uiCaption)
                .foregroundStyle(Semantic.foreground)
                .lineLimit(1)
            Spacer(minLength: Space.x2)
            clock
            if let onStop {
                // Beside the clock on purpose: the two things you want while
                // waiting are how long it has been and how to make it stop.
                Button(action: onStop) {
                    Text(JobCardCopy.stop)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
                .buttonStyle(.plain)
                .help(JobCardCopy.stop)
            }
        }
    }

    /// The seconds are the honest part of the wait: a card with no clock and
    /// no step reads as frozen.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(JobSteps.worked(
                context.date.timeIntervalSince(job.startedAt),
                Localized.language()))
                .font(.uiMonoSm)
                .foregroundStyle(Semantic.mutedForeground)
                .monospacedDigit()
        }
    }

    /// The first seconds: the job is running but no step has arrived yet.
    /// A skeleton, not silence.
    private var warmup: some View {
        Capsule()
            .fill(Semantic.hover)
            .frame(width: Space.x1 * 34, height: Space.x2)
            .shimmering(active: true)
    }

    private var accessibilityText: String {
        let what = job.goal ?? JobCardCopy.working
        guard let last = job.steps.last else { return what }
        return "\(what). \(last.label)"
    }
}

enum JobCardCopy {
    static var working: String { Localized.string("job.working") }
    static var stop: String { Localized.string("job.stop") }
}

/// The step timeline, Grok-style: an icon per tool, a thread joining them,
/// and the detail in mono. The last row is the one running now — the shimmer
/// says "this is where I am", the rest stand still as history.
struct JobTimelineView: View {
    let steps: [JobStepInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                row(step, isLast: index == steps.count - 1)
            }
        }
    }

    private func row(_ step: JobStepInfo, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.x2) {
            VStack(spacing: Space.none) {
                Image(systemName: JobSteps.icon(for: step.tool))
                    .font(.uiMicro)
                    .foregroundStyle(isLast
                        ? Semantic.accentText : Semantic.mutedForeground)
                    .frame(width: Space.x4, height: Space.x4)
                if !isLast {
                    // Fixed height, never minHeight: a Rectangle is greedy and
                    // stretches to fill the scroll if you let it.
                    Rectangle()
                        .fill(Semantic.border)
                        .frame(width: 1, height: Space.x2)
                }
            }
            // A thought reads as inner voice, not as an action.
            Text(step.label)
                .font(.uiMonoSm)
                .italic(step.tool == JobSteps.Thinking.tool)
                .foregroundStyle(isLast && step.tool != JobSteps.Thinking.tool
                    ? Semantic.foreground : Semantic.mutedForeground)
                .lineLimit(1)
                .truncationMode(.middle)
                .shimmering(active: isLast)
            Spacer(minLength: Space.none)
        }
    }
}
