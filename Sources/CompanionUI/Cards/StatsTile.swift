import CompanionCore
import Charts
import SwiftUI

/// One figure: the number counts up into place, the delta carries its sign's
/// colour, and an optional trend draws as a sparkline in the same colour.
struct StatsTile: View {
    let item: StatsBlock.Item

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                FigureValue(text: item.value)
                    .font(.uiTitle)
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let delta = item.delta, !delta.isEmpty {
                    Text(delta)
                        .font(.uiCaption)
                        .foregroundStyle(DataCardInk.delta(delta))
                }
            }
            Text(item.label)
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .lineLimit(2)
            if let trend = item.trend {
                Sparkline(values: trend, tone: DataCardInk.delta(item.delta ?? ""))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A figure that counts from zero to its value. Text the model wrote that is
/// not a number shows as it is.
private struct FigureValue: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        if let figure = StatsFigure(text) {
            Text(verbatim: shown == figure.number ? text : figure.text(at: shown))
                .contentTransition(.numericText(value: shown))
                .task(id: text) {
                    withAnimation(ChromeMotion.animation(.expoOut(MotionTime.enter), reduceMotion: reduceMotion)) {
                        shown = figure.number
                    }
                }
        } else {
            Text(verbatim: text)
        }
    }
}

/// No axes, no labels: the shape is the point, the numbers are in the tile.
private struct Sparkline: View {
    let values: [Double]
    let tone: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("step", index), y: .value("value", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: CardMetrics.sparkline)
        .accessibilityHidden(true)
    }
}
