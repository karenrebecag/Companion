import CompanionCore
import SwiftUI

// Wave 16m-2: the working states, measured on Incredible's overlay CSS
// (docs/research/incredible-isla-componentes.md §2) — the live transcript's
// two inks, the reel of touched apps, the runcard with its steps, the
// checklist for long jobs and the sub-agent bars.

package enum WorkStateMetrics {
    /// wf-runcard: 320–420 wide, 14/16/12 padding, radius 20 over #16161b.
    package static let runMinWidth: CGFloat = 320
    package static let runMaxWidth: CGFloat = 420
    package static let runPaddingTop: CGFloat = 14
    package static let runPaddingX: CGFloat = 16
    package static let runPaddingBottom: CGFloat = 12
    package static let runRadius: CGFloat = 20
    package static let runShadowAlpha = 0.32
    package static let runShadowRadius: CGFloat = 48 / 2
    package static let runShadowY: CGFloat = 18
    /// wf-runstep: 5 × 2 padding, gap 2.
    package static let stepPaddingY: CGFloat = 5
    package static let stepPaddingX: CGFloat = 2
    package static let stepGap: CGFloat = 2
    /// wf-checklist: 320 wide, 18/20/12 padding.
    package static let checklistWidth: CGFloat = 320
    package static let checklistPaddingTop: CGFloat = 18
    package static let checklistPaddingX: CGFloat = 20
    package static let checklistPaddingBottom: CGFloat = 12
    /// Past this many steps the runcard reads as a checklist.
    package static let checklistAt = 5
    /// The reel of touched apps is a 26-pt band.
    package static let reelHeight: CGFloat = 26
    /// The reel's item is model-chosen text: past this many characters it
    /// is cut, so the chip and VoiceOver carry the same bounded string.
    package static let reelItemMax = 60
    /// Live transcription: 14/500 at 72 %, settling to 94 % once fixed.
    package static let transcriptSize: CGFloat = 14
    package static let transcriptLeading: CGFloat = 1.5
    package static let transcriptLive = 0.72
    package static let transcriptFixed = 0.94
    /// The tiny fate marks (check / x) beside a step.
    package static let markSize: CGFloat = 9
    /// The checklist paints a window on long jobs, not the whole scroll.
    package static let checklistVisibleSteps = 12

    /// sub-agent-bars: one bar per live agent, gap 10.
    package static let agentGap: CGFloat = 10

    package static let runSurface = Color(
        red: 0x16 / 255, green: 0x16 / 255, blue: 0x1B / 255)

    /// The steps a runcard shows are the tail: the card is a window on the
    /// work, the window's timeline keeps the whole story.
    package static let runVisibleSteps = 4

    /// The live sub-agents: Task steps that have not come back yet.
    package static func agents(_ steps: [JobStepInfo]) -> [JobStepInfo] {
        steps.filter { ($0.tool == "Task" || $0.tool == "Agent") && !$0.done }
    }
}

/// What the ear hears, in its own voice: quieter while it can still change,
/// full ink the moment it is fixed.
struct IslandTranscript: View {
    let text: String
    let fixed: Bool

    var body: some View {
        Text(text)
            .font(Fonts.geist(WorkStateMetrics.transcriptSize).weight(.medium))
            .lineSpacing(AnswerBlockMetrics.lineSpacing(
                size: WorkStateMetrics.transcriptSize,
                leading: WorkStateMetrics.transcriptLeading))
            .foregroundStyle(.white.opacity(
                fixed ? WorkStateMetrics.transcriptFixed : WorkStateMetrics.transcriptLive))
            .lineLimit(2)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.expoOut(MotionTime.fast), value: fixed)
    }
}

/// The app this turn touched last: a quiet band under the status line with
/// one item, as Incredible's reel (K8). A row of every app crowded the band,
/// and an empty target painted an empty chip.
struct IslandReel: View {
    static func item(_ touched: [String]) -> String? {
        touched.lazy.map(shown).last { !$0.isEmpty }
    }

    /// Invisible characters (bidi overrides, zero-width, blank glyphs) can
    /// hide part of a model-chosen name from the eye and from VoiceOver, so
    /// they go; breaks become spaces so words stay apart. The scalar budget
    /// bounds combining marks, which a grapheme count alone lets through
    /// (security and QA review #212).
    private static func shown(_ target: String) -> String {
        var kept = String.UnicodeScalarView()
        var budget = WorkStateMetrics.reelItemMax * 4
        for scalar in target.unicodeScalars {
            guard let next = Self.kept(scalar) else { continue }
            kept.append(next)
            budget -= 1
            if budget == 0 { break }
        }
        let visible = String(kept).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard visible.count > WorkStateMetrics.reelItemMax else { return visible }
        let cut = String(visible.prefix(WorkStateMetrics.reelItemMax - 1))
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func kept(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let properties = scalar.properties
        switch properties.generalCategory {
        case .lineSeparator, .paragraphSeparator: return " "
        case .control: return properties.isWhitespace ? " " : nil
        case .format: return nil
        default:
            // U+2800 renders blank but is not default-ignorable.
            return properties.isDefaultIgnorableCodePoint || scalar == "\u{2800}" ? nil : scalar
        }
    }

    /// What VoiceOver reads: the band's name, then the app. Since K9 the
    /// status line says "Pensando", so the reel is the only place that names
    /// the app the agent is acting in (security review K9).
    static func spoken(_ item: String) -> (label: String, value: String) {
        (Localized.string("island.reel"), item)
    }

    let item: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.x1) {
            ReferentChip(text: item)
                .id(item)
                .transition(.opacity)
            Spacer(minLength: Space.none)
        }
        .animation(reduceMotion ? nil : .expoOut(MotionTime.reelSwap), value: item)
        .frame(height: WorkStateMetrics.reelHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spoken(item).label)
        .accessibilityValue(Self.spoken(item).value)
    }
}

/// One step row: the tool's glyph, its words, and its fate on the right.
private struct WorkStepRow: View {
    let step: JobStepInfo
    let running: Bool

    var body: some View {
        HStack(spacing: Space.x2) {
            Image(systemName: JobSteps.icon(for: step.tool))
                .font(GeistFont.uiMicro)
                .foregroundStyle(.white.opacity(IslandAlpha.muted))
                .frame(width: AnswerBlockMetrics.glyphWidth)
            Text(step.label)
                .font(Fonts.geist(TypeSize.caption))
                .foregroundStyle(.white.opacity(
                    step.done ? IslandAlpha.secondary : IslandAlpha.text))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Space.none)
            if step.failed {
                Image(systemName: "xmark")
                    .font(Fonts.geist(WorkStateMetrics.markSize).weight(.semibold))
                    .foregroundStyle(IslandPalette.error.color)
            } else if step.done {
                Image(systemName: "checkmark")
                    .font(Fonts.geist(WorkStateMetrics.markSize).weight(.semibold))
                    .foregroundStyle(.white.opacity(IslandAlpha.secondary))
            } else if running {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, WorkStateMetrics.stepPaddingY)
        .padding(.horizontal, WorkStateMetrics.stepPaddingX)
    }
}

/// The dark work surface both cards share.
struct WorkSurface: ViewModifier {
    var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .frame(minWidth: width ?? WorkStateMetrics.runMinWidth,
                   maxWidth: width ?? WorkStateMetrics.runMaxWidth,
                   alignment: .leading)
            .background(RoundedRectangle(cornerRadius: WorkStateMetrics.runRadius)
                .fill(WorkStateMetrics.runSurface))
            .overlay(RoundedRectangle(cornerRadius: WorkStateMetrics.runRadius)
                .strokeBorder(.white.opacity(IslandAlpha.border), lineWidth: Stroke.hairline))
            .shadow(color: .black.opacity(WorkStateMetrics.runShadowAlpha),
                    radius: WorkStateMetrics.runShadowRadius, y: WorkStateMetrics.runShadowY)
    }
}

/// The execution card: the goal, then the last few steps with their fate.
struct IslandRunCard: View {
    let job: JobTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: WorkStateMetrics.stepGap) {
            if let goal = job.goal, !goal.isEmpty {
                Text(goal)
                    .font(Fonts.geist(TypeSize.body).weight(.medium))
                    .foregroundStyle(.white.opacity(IslandAlpha.text))
                    .lineLimit(1)
                    .padding(.bottom, Space.x1)
            }
            // Absolute indices: a growing tail must not re-key every row
            // (review 16m — the spinner jumped identity on each append).
            let tail = Array(job.steps.enumerated())
                .suffix(WorkStateMetrics.runVisibleSteps)
            ForEach(tail, id: \.offset) { index, step in
                WorkStepRow(step: step, running: index == job.steps.count - 1 && !step.done)
            }
        }
        .padding(.top, WorkStateMetrics.runPaddingTop)
        .padding(.horizontal, WorkStateMetrics.runPaddingX)
        .padding(.bottom, WorkStateMetrics.runPaddingBottom)
        .modifier(WorkSurface())
    }
}

/// The long job's checklist: a done-count badge, every step, a dismiss.
struct IslandChecklist: View {
    let job: JobTimeline
    let onDismiss: () -> Void

    /// "3/7": counts, not copy — the fraction reads the same everywhere.
    private static func badge(_ steps: [JobStepInfo]) -> String {
        "\(steps.filter(\.done).count)/\(steps.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkStateMetrics.stepGap) {
            HStack(spacing: Space.x2) {
                if let goal = job.goal, !goal.isEmpty {
                    Text(goal)
                        .font(Fonts.geist(TypeSize.body).weight(.medium))
                        .foregroundStyle(.white.opacity(IslandAlpha.text))
                        .lineLimit(1)
                }
                Spacer(minLength: Space.none)
                Text(Self.badge(job.steps))
                    .font(Fonts.geist(TypeSize.micro).weight(.semibold))
                    .foregroundStyle(.white.opacity(IslandAlpha.secondary))
                    .padding(.horizontal, Space.x2)
                    .padding(.vertical, WorkStateMetrics.stepPaddingX)
                    .background(Capsule().fill(.white.opacity(IslandAlpha.tile)))
                CloseButton(variant: .island, label: Localized.string("island.checklist.dismiss"),
                            action: onDismiss)
            }
            .padding(.bottom, Space.x1)
            let tail = Array(job.steps.enumerated())
                .suffix(WorkStateMetrics.checklistVisibleSteps)
            ForEach(tail, id: \.offset) { index, step in
                WorkStepRow(step: step, running: index == job.steps.count - 1 && !step.done)
            }
        }
        .padding(.top, WorkStateMetrics.checklistPaddingTop)
        .padding(.horizontal, WorkStateMetrics.checklistPaddingX)
        .padding(.bottom, WorkStateMetrics.checklistPaddingBottom)
        .modifier(WorkSurface(width: WorkStateMetrics.checklistWidth))
    }
}

/// One quiet bar per sub-agent still out working.
struct IslandAgentBars: View {
    let agents: [JobStepInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: WorkStateMetrics.agentGap) {
            ForEach(Array(agents.enumerated()), id: \.offset) { _, agent in
                HStack(spacing: Space.x2) {
                    Image(systemName: "person.2")
                        .font(GeistFont.uiMicro)
                        .foregroundStyle(.white.opacity(IslandAlpha.muted))
                    Text(agent.label)
                        .font(Fonts.geist(TypeSize.caption))
                        .foregroundStyle(.white.opacity(IslandAlpha.secondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ProgressView().controlSize(.mini)
                }
            }
        }
    }
}
