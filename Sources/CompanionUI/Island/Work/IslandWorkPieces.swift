import CompanionCore
import SwiftUI

// Wave 16m-2: the working states, measured on Incredible's overlay CSS
// (docs/research/incredible-isla-componentes.md §2) — the live transcript's
// two inks, the reel of touched apps, the shared work surface and the
// sub-agent bars. The run card's pure model is in IslandRunCardModel.swift.

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

    /// sub-agent-bars: one bar per live agent, gap 10.
    package static let agentGap: CGFloat = 10

    package static let runSurface = Color(
        red: 0x16 / 255, green: 0x16 / 255, blue: 0x1B / 255)

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

private typealias M = RunCardMetrics

/// The run card: every step of the job with its real state and time. The
/// card sits in the island's flow and the island grows downward: Companion's
/// island lives at the notch, so there is no "above" (Incredible's floats
/// 10 pt above an island at the screen bottom, firstRun-BOTAwJJ8.css @394242).
struct IslandRunCard: View {
    let job: JobTimeline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            card(now: context.date)
        }
    }

    private func card(now: Date) -> some View {
        let rows = RunCardModel.rows(steps: job.steps, now: now)
        return VStack(alignment: .leading, spacing: M.rowGap) {
            header(now: now)
            // A deviation from the reference: Incredible's workflows are
            // bounded and our tool calls are not. The card never caps itself:
            // the island's own column caps and scrolls it with its siblings.
            RunCardRowList(rows: rows, spins: RunCardModel.spins(reduceMotion: reduceMotion))
        }
        .padding(.top, M.padTop)
        .padding(.horizontal, M.padSide)
        .padding(.bottom, M.padBottom)
        .frame(minWidth: M.minWidth, maxWidth: M.maxWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: M.radius).fill(IslandInk.runCardBg))
        .shadow(color: IslandInk.runCardShadowNear,
                radius: M.shadowNearBlur * M.cssBlurToRadius, y: M.shadowNearY)
        .shadow(color: IslandInk.runCardShadowFar,
                radius: M.shadowFarBlur * M.cssBlurToRadius, y: M.shadowFarY)
        .accessibilityElement(children: .contain)
    }

    private func header(now: Date) -> some View {
        HStack(spacing: M.headGap) {
            if let goal = job.goal.map(RunCardModel.goal), !goal.isEmpty {
                Text(goal)
                    .font(Fonts.geist(M.titleSize).weight(M.titleWeight))
                    .foregroundStyle(IslandInk.runTitleLive)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Space.none)
            Text(RunCardModel.meta(jobStartedAt: job.startedAt, now: now))
                .font(Fonts.geist(M.metaSize).monospacedDigit())
                .foregroundStyle(.white.opacity(M.metaOpacity))
        }
        .padding(.bottom, M.headBottom)
    }
}

struct RunCardRowList: View {
    let rows: [RunCardRow]
    let spins: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: M.rowGap) {
            ForEach(rows) { RunCardRowView(row: $0, spins: spins) }
        }
    }
}

private struct RunCardRowView: View {
    let row: RunCardRow
    let spins: Bool

    private var titleInk: Color {
        switch row.state {
        case .done: IslandInk.runTitleDone
        case .failed: IslandInk.runTitleFailed
        case .live: IslandInk.runTitleLive
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: M.mainGap) {
            glyph.padding(.top, M.glyphTop)
            Text(row.title)
                .font(Fonts.geist(M.stepTitleSize)
                    .weight(row.state == .live ? .semibold : .regular))
                .foregroundStyle(titleInk)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let duration = row.duration {
                Text(duration)
                    .font(Fonts.geist(M.durationSize).monospacedDigit())
                    .foregroundStyle(row.durationIsLive
                        ? IslandInk.runDurationLive : IslandInk.runDurationFinished)
                    .padding(.leading, M.durationLead)
            }
        }
        .padding(.vertical, M.rowPadV)
        .padding(.horizontal, M.rowPadH)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Localized.string(RunCardModel.stateKey(row.state)))
    }

    @ViewBuilder private var glyph: some View {
        switch RunCardModel.glyph(for: row.state) {
        case .symbol(let name):
            Circle().fill(row.state == .failed ? IslandInk.runGlyphFailedBg : IslandInk.runGlyphDoneBg)
                .frame(width: M.glyphSide, height: M.glyphSide)
                .overlay(Image(systemName: name)
                    .font(Fonts.geist(M.glyphFont).weight(M.glyphWeight))
                    .foregroundStyle(row.state == .failed
                        ? IslandInk.runGlyphFailedInk : IslandInk.runGlyphDoneInk)
                    .accessibilityHidden(true))
        case .spinner:
            RunCardSpinner(spins: spins).frame(width: M.glyphSide, height: M.glyphSide)
                .accessibilityHidden(true)
        }
    }
}

private struct RunCardSpinner: View {
    let spins: Bool
    @State private var turned = false

    var body: some View {
        Circle().stroke(IslandInk.runSpinnerTrack, lineWidth: M.spinnerStroke)
            .overlay(Circle().trim(from: 0, to: M.spinnerArcFraction)
                .stroke(IslandInk.runSpinnerArc, lineWidth: M.spinnerStroke)
                // trim starts at 3 o'clock; the CSS border-top starts at 12.
                .rotationEffect(.degrees(-90 + (turned ? 360 : 0))))
            .frame(width: M.spinnerSide, height: M.spinnerSide)
            .onAppear { turn(spins) }
            .onChange(of: spins) { _, now in turn(now) }
    }

    private func turn(_ spinning: Bool) {
        if spinning {
            withAnimation(.linear(duration: M.spinnerPeriod).repeatForever(autoreverses: false)) {
                turned = true
            }
        } else {
            withAnimation(nil) { turned = false }
        }
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
