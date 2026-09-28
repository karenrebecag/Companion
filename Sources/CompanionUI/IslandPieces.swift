import CompanionCore
import SwiftUI

/// Incredible's notch bar is black in light and dark alike: it reads as an
/// extension of the notch, not as a window of the theme (spec 16c §2).
enum IslandInk {
    // 16l-4: Incredible's `--ci-*` whites over black.
    static var panel: Color { Neutral.black.color }
    static var text: Color { white(IslandAlpha.text) }
    static var secondary: Color { white(IslandAlpha.secondary) }
    static var muted: Color { white(IslandAlpha.muted) }
    static var chip: Color { white(IslandAlpha.tile) }
    static var chipPressed: Color { white(IslandAlpha.tileHover) }
    static var field: Color { white(IslandAlpha.tile) }
    /// The composer field and its idle send button, sampled from Incredible.
    static var fieldFill: Color { white(IslandFieldMetrics.fill) }
    static var sendIdle: Color { white(IslandFieldMetrics.sendFill) }
    static var hairline: Color { white(IslandAlpha.border) }
    static var divider: Color { white(IslandAlpha.divider) }
    static var rim: Color { white(IslandMetrics.rimAlpha) }
    /// Only the open panel casts one; at rest it is hardware.
    static var shadow: Color { Neutral.black.color.opacity(0.35) }
    static var amber: Color { Accent.orange.color }
    static var green: Color { Palette.signalGreen.color }
    static var destructive: Color { IslandPalette.error.color }
    static let radius: CGFloat = IslandMetrics.openRadius
    static let cardRadius: CGFloat = AnswerOptionMetrics.radius
    static let lightSide: CGFloat = 8
    static let slotSide: CGFloat = 22
    /// A word not yet said: the secondary ink's weight on black.
    static let dimWord: Double = 0.62
    static let sendSide: CGFloat = IslandMetrics.sendSide
    static let barWidth: CGFloat = 3
    static let chipVertical: CGFloat = 6
    /// Incredible's dropdowns sit a step lighter than the panel they open from.
    static var popover: Color { Neutral.n800.color }
    /// Incredible's tooltip pill (16o research).
    static var tooltip: Color { Swatch("17181B").color }
    static var blue: Color { IslandPalette.accent.color }
    static var blueTile: Color { IslandPalette.accent.color.opacity(0.18) }
    static var stop: Color { Swatch("FF453A").color }

    private static func white(_ alpha: Double) -> Color { Neutral.white.color.opacity(alpha) }
    static let noticeTile: CGFloat = 40
    /// The countdown ring moves a few pixels a second; more frames buy nothing.
    static let ringFrame: Double = 1.0 / 15
}

/// Amber = it needs you, green = done. A dot, never a word.
struct IslandLight: View {
    let light: IslandState.Light
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let color {
                // Success check, small: it pops in with the one allowed bob.
                Circle()
                    .fill(color)
                    .frame(width: IslandInk.lightSide, height: IslandInk.lightSide)
                    .shadow(color: color.opacity(0.7), radius: IslandInk.lightSide / 2)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    .id(light)
                    .accessibilityLabel(Localized.string(
                        light == .amber ? "island.light.amber" : "island.light.green"))
            }
        }
        .animation(reduceMotion ? .expoOut(MotionTime.fast) : MotionSpring.success.animation, value: light)
    }

    private var color: Color? {
        switch light {
        case .none: nil
        case .amber: IslandInk.amber
        case .green: IslandInk.green
        }
    }
}

/// The listening pill: bars that follow the microphone, no status words.
struct IslandWaveBars: View {
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let weights: [Double] = [0.45, 0.8, 1, 0.7, 0.4]
    private static let minHeight: CGFloat = 4
    private static let maxHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: IslandInk.barWidth) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .fill(IslandInk.text)
                    .frame(width: IslandInk.barWidth, height: height(Self.weights[index]))
            }
        }
        .frame(height: Self.maxHeight)
        .animation(reduceMotion ? nil : .expoOut(MotionTime.follow), value: level)
        .accessibilityHidden(true)
    }

    private func height(_ weight: Double) -> CGFloat {
        let live = min(max(level, 0), 1) * weight
        return Self.minHeight + (Self.maxHeight - Self.minHeight) * CGFloat(live)
    }
}

/// A grey chip, Incredible's secondary control.
struct IslandChipStyle: ButtonStyle {
    var tint: Color = IslandInk.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GeistFont.uiCaption)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.x3)
            .padding(.vertical, IslandInk.chipVertical)
            .background(Capsule().fill(configuration.isPressed ? IslandInk.chipPressed : IslandInk.chip))
            .contentShape(Capsule())
    }
}

/// Wave 17 (spec §3 "Se ve"): the bridge's chip, label plus its own stop
/// button so "Detener manos" is one tap wherever the client's name shows.
/// Pulses once per write action — an agent moving the pointer unannounced is
/// the thing that frightens; the blink is the announcement.
struct IslandHandsChip: View {
    let client: String
    let pulse: Int
    let onStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: Space.x2) {
            Text(String(format: Localized.string("island.hands"), client))
                .font(GeistFont.uiCaption)
                .foregroundStyle(IslandInk.text)
                .opacity(pulsing ? IslandHandsMetrics.pulseOpacity : 1)
                .scaleEffect(pulsing ? IslandHandsMetrics.pulseScale : 1)
            Button(IslandCopy.action(.stopHands)) { onStop() }
                .buttonStyle(IslandChipStyle())
        }
        .animation(IslandMotionBudget.textSwap.animation(reduceMotion: reduceMotion), value: pulsing)
        .onChange(of: pulse) { _, _ in
            guard !reduceMotion else { return }
            pulsing = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(IslandMotionBudget.textSwap.duration))
                pulsing = false
            }
        }
    }
}

private enum IslandHandsMetrics {
    static let pulseOpacity: Double = 0.55
    static let pulseScale: CGFloat = 1.04
}

/// One reply as a card: a title, one line, "View →" for the rest.
struct IslandResultCard: View {
    let result: IslandResult
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(result.title)
                    .font(Fonts.geist(TypeSize.base).weight(.medium))
                    .foregroundStyle(IslandInk.text)
                    .lineLimit(1)
                if let line = result.line {
                    Text(line)
                        .font(GeistFont.uiCaption)
                        .foregroundStyle(IslandInk.secondary)
                        .lineLimit(1)
                }
                Text(Localized.string("island.result.open"))
                    .font(GeistFont.uiCaption)
                    .foregroundStyle(IslandInk.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.x3)
            .background(RoundedRectangle(cornerRadius: IslandInk.cardRadius).fill(IslandInk.field))
            .contentShape(RoundedRectangle(cornerRadius: IslandInk.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

/// Incredible's field (16n, from the 20:13 screenshot): the orb outside, then
/// one rounded field that holds the words, the clip and send. Volume and the
/// menu live in the notch band (`IslandHeaderControls`); their popovers drop
/// from there through the portal (16o-1).
struct IslandComposer: View {
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let mark: AnyView
    let onSend: () -> Void
    let onAttach: () -> Void
    @State private var clipHover = false

    var body: some View {
        HStack(spacing: IslandFieldMetrics.orbGap) {
            mark.islandTooltip(Localized.string("island.tip.talk"))
            field
        }
    }

    private var field: some View {
        HStack(spacing: Space.none) {
            TextField(Localized.string("island.ask"), text: $draft)
                .textFieldStyle(.plain)
                .font(Fonts.geist(TypeSize.rowTitle))
                .foregroundStyle(IslandInk.text)
                .focused(focused)
                .onSubmit(onSend)
                .padding(.leading, IslandFieldMetrics.textInset)
            Button(action: onAttach) {
                Image(systemName: "paperclip")
                    .font(.system(size: TypeSize.sectionTitle, weight: .regular))
                    .foregroundStyle(clipHover ? IslandInk.text : IslandInk.secondary)
                    .frame(width: IslandFieldMetrics.tool, height: IslandFieldMetrics.tool)
                    .background(Circle().fill(clipHover ? IslandInk.chipPressed : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { clipHover = $0 }
            .accessibilityLabel(Localized.string("island.attach"))
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: TypeSize.body, weight: .semibold))
                    .foregroundStyle(ready ? IslandInk.panel : IslandInk.muted)
                    .frame(width: IslandFieldMetrics.send, height: IslandFieldMetrics.send)
                    .background(Circle().fill(ready ? IslandInk.text : IslandInk.sendIdle))
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .islandTooltip(Localized.string("island.tip.send"))
            .accessibilityLabel(Localized.string("island.send"))
            .padding(.leading, Space.x1)
        }
        .padding(.trailing, IslandFieldMetrics.trailing)
        .frame(height: IslandFieldMetrics.height)
        .background(RoundedRectangle(cornerRadius: IslandFieldMetrics.radius).fill(IslandInk.fieldFill))
    }

    private var ready: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// The destructive entry asks once, inside the panel: a sheet or an alert
/// would need the window this panel never is.
struct IslandClearConfirm: View {
    let onClear: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Space.x2) {
            Text(Localized.string("island.clear.ask"))
                .font(GeistFont.uiCaption)
                .foregroundStyle(IslandInk.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(Localized.string("island.clear.no"), action: onCancel)
                .buttonStyle(IslandChipStyle())
            Button(Localized.string("island.clear.yes"), action: onClear)
                .buttonStyle(IslandChipStyle(tint: IslandInk.destructive))
        }
    }
}

/// The reply as the panel shows it (16f): large plain words, no bubble, the
/// part that was said. The rest lives in the window.
enum IslandReplyText {
    static let maxLength = 240

    static func spoken(from reply: String) -> String {
        let paragraph = reply.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        // Model text is unbounded and this runs on every streamed token: cut
        // first, so the cost never depends on the reply (security review 16f).
        var text = String(paragraph.prefix(maxLength * 4))
        // [label](url) reads as its label; a "[" that opens no link is
        // skipped, not the end of the search.
        var from = text.startIndex
        while let open = text.range(of: "[", range: from..<text.endIndex) {
            guard let mid = text.range(of: "](", range: open.upperBound..<text.endIndex),
                  let close = text.range(of: ")", range: mid.upperBound..<text.endIndex),
                  !text[open.upperBound..<mid.lowerBound].contains("[")
            else {
                from = open.upperBound
                continue
            }
            let label = String(text[open.upperBound..<mid.lowerBound])
            // Indices do not survive a mutation; the offset does.
            let resume = text.distance(from: text.startIndex, to: open.lowerBound) + label.count
            text.replaceSubrange(open.lowerBound..<close.upperBound, with: label)
            from = text.index(text.startIndex, offsetBy: resume)
        }
        text = text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*- ").union(.whitespaces))
        return text.count > maxLength ? String(text.prefix(maxLength)) + "…" : text
    }
}

struct IslandReply: View {
    let text: String
    let startedAt: Date
    let speaking: Bool

    /// Smooth enough for a 150 ms fade per word, a fraction of a display's rate.
    private static let frameInterval = 1.0 / 30

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !speaking)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            Text(Self.painted(words, elapsed: elapsed, speaking: speaking))
                .font(Fonts.geist(TypeSize.strong))
                .lineSpacing(Space.x1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel(text)
    }

    /// Dim words read as the secondary ink on black; each brightens to full
    /// over its own fade, so the light glides along the line.
    private static func painted(_ words: [String], elapsed: Double, speaking: Bool) -> AttributedString {
        var out = AttributedString()
        for (index, word) in words.enumerated() {
            let light = IslandReveal.brightness(word: index, elapsed: elapsed, speaking: speaking)
            var piece = AttributedString(index == 0 ? word : " " + word)
            piece.foregroundColor = IslandInk.text.opacity(IslandInk.dimWord + (1 - IslandInk.dimWord) * light)
            out += piece
        }
        return out
    }
}

/// Where running tasks sit, top right (16f): three slots, the first one
/// turning while a job runs.
struct IslandSlots: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        HStack(spacing: Space.x2) {
            ForEach(0..<3, id: \.self) { index in
                ZStack {
                    Circle()
                        .strokeBorder(IslandInk.secondary, style: StrokeStyle(lineWidth: Stroke.thin, dash: [3, 4]))
                    if index == 0, active {
                        Circle()
                            .trim(from: 0, to: 0.3)
                            .stroke(IslandInk.text, style: StrokeStyle(lineWidth: Stroke.medium, lineCap: .round))
                            .rotationEffect(.degrees(turning ? 360 : 0))
                            .onAppear {
                                guard !reduceMotion else { return }
                                withAnimation(.linear(duration: MotionTime.panel * 4).repeatForever(autoreverses: false)) {
                                    turning = true
                                }
                            }
                    }
                }
                .frame(width: IslandInk.slotSide, height: IslandInk.slotSide)
            }
        }
        .accessibilityHidden(!active)
        .accessibilityLabel(Localized.string("island.job"))
    }
}
