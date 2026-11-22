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
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Color.secondary.opacity(0.35))
                AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.narrow)).font(.caption2).foregroundStyle(.secondary)
            }
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
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}
