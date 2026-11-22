import SwiftUI
import Charts

struct MetricPoint: Identifiable, Hashable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Grafiek in de stijl van Homey Insights: vloeiende lijn met verloopvlak, gestippeld raster, selectie met ring-punt.
struct InsightsChart: View {
    let points: [MetricPoint]
    let unit: String
    let color: Color
    /// Labels onder de X-as: dag + maandletter, of bij een jaar alleen de maandletter (J F M A …).
    var xFormat: Date.FormatStyle = .dateTime.day().month(.narrow)
    @Binding var selected: MetricPoint?
    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Dag", p.date, unit: .day), y: .value(unit, p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Dag", p.date, unit: .day), y: .value(unit, p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let s = selected {
                RuleMark(x: .value("Dag", s.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Dag", s.date, unit: .day), y: .value(unit, s.value))
                    .symbol {
                        Circle().fill(Color.black).frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(color, lineWidth: 2))
                    }
            }
        }
        .chartYScale(domain: 0...max(4, (points.map(\.value).max() ?? 0) * 1.15))
        // eenheid bovenaan de Y-as, zoals Homey
        .chartYAxisLabel(position: .topLeading, spacing: 6) {
            Text(verbatim: unit).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Theme.insightsGrid)
                AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: xFormat).font(.caption2).foregroundStyle(.secondary)
            }
        }
        // dunne doorgetrokken lijn langs de Y-as en de X-as, geen verticale rasterlijnen
        .chartPlotStyle { plot in
            plot
                .overlay(alignment: .leading) { Rectangle().fill(Theme.insightsGrid).frame(width: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.insightsGrid).frame(height: 1) }
        }
        .chartXSelection(value: $selectedDate)
        .onChange(of: selectedDate) { _, date in
            guard let date else { selected = nil; return }
            selected = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        .frame(height: 220)
        .accessibilityLabel(Text(verbatim: unit))
    }
}

/// Pil-segmenten zoals Homey.
struct PillSegments<T: Hashable>: View {
    let items: [(T, LocalizedStringKey)]
    @Binding var selection: T
    /// Voorleestekst per segment als het label alleen een letter is (W = week …).
    var spoken: [T: LocalizedStringKey] = [:]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { item in
                Button { selection = item.0 } label: {
                    Text(item.1)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selection == item.0 ? Color.primary.opacity(0.15) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == item.0 ? .primary : .secondary)
                .accessibilityLabel(Text(spoken[item.0] ?? item.1))
                .accessibilityAddTraits(selection == item.0 ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.insightsPill, in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}
