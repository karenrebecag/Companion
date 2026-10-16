import CompanionCore
import CompanionUIPro
import SwiftUI

/// A dated timeline uses the feed component. Steps and undated events have no
/// time to place them on, so they draw as an ordered rail instead of with
/// invented hours.
struct PresentTimelineView: View {
    let timeline: PresentTimeline
    let measures: PresentMeasures

    var body: some View {
        if let events = dated {
            Timeline(
                events: events, now: Date(),
                label: PresentStrings.label(timeline.title, fallback: "present.timeline"),
                maxHeight: measures.timelineMaxHeight)
        } else {
            PresentRail(events: timeline.events)
        }
    }

    private var dated: [TimelineEvent]? {
        guard !timeline.events.isEmpty, timeline.events.allSatisfy({ $0.startsAt != nil }) else { return nil }
        return timeline.events.enumerated().compactMap { index, event in
            event.startsAt.map {
                TimelineEvent(
                    id: "\(index)", at: $0, title: event.title,
                    meta: [event.when, event.place].compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                    tone: Self.tone(event.tone),
                    detail: event.detail.map { AnyView(Text($0)) })
            }
        }
    }

    /// The feed has three tones; warning and info read as neutral there.
    private static func tone(_ tone: PresentTone) -> TimelineTone {
        switch tone {
        case .success: .success
        case .danger: .danger
        case .neutral, .info, .warning: .neutral
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Events in the order the model gave them, each with the words it wrote.
struct PresentRail: View {
    let events: [PresentEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                HStack(alignment: .top, spacing: Space.x3) {
                    VStack(spacing: Space.none) {
                        Circle()
                            .fill(PresentNotice.ink(event.tone))
                            .frame(width: PresentMeasures.railDot, height: PresentMeasures.railDot)
                            .padding(.top, Space.x1_5)
                        if index < events.count - 1 {
                            Rectangle().fill(Semantic.border).frame(width: Stroke.hairline)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: PresentMeasures.railDot)
                    VStack(alignment: .leading, spacing: Space.x0_5) {
                        Text(event.title)
                            .font(.uiBody)
                            .foregroundStyle(Semantic.foreground)
                        if let line = Self.line(event) {
                            Text(line)
                                .font(.uiCaption)
                                .foregroundStyle(Semantic.mutedForeground)
                        }
                        if let detail = event.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.uiCaption)
                                .foregroundStyle(Semantic.mutedForeground)
                        }
                    }
                    .padding(.bottom, index < events.count - 1 ? Space.x3 : Space.none)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    static func line(_ event: PresentEvent) -> String? {
        let text = [event.when, event.place].compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

/// One upcoming deadline counted down to the second.
struct PresentCountdown: View {
    let event: PresentEvent
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(event.title)
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.foreground)
            if let line = PresentRail.line(event) {
                Text(line)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            if let start = event.startsAt {
                Countdown(
                    target: start, variant: compact ? .compact : .large,
                    completeLabel: Localized.string("present.countdown.done"),
                    label: Localized.string("present.countdown.label"),
                    unitLabel: PresentStrings.unit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
