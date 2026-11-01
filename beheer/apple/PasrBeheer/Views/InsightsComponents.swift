import Charts
import SwiftUI

/// Periode van de grafieken (`days` van de actie `stats`).
enum StatsRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, year = 365
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Maand"
        case .quarter: "Kwartaal"
        case .year: "Jaar"
        }
    }

    /// Zo ver terug als de server bewaart (offset × days ≤ 1100).
    var maxOffset: Int { 1100 / rawValue - 1 }
}

/// Eén punt in een grafiek (een dag, of bij een jaar een week).
struct InsightPoint: Identifiable {
    let date: Date
    let end: Date?
    let values: [Metric: Int?]
    var id: Date { date }
}

/// Dagen van de periode; bij een jaar per week (staven opgeteld, lijnen de laatste waarde van de week).
func insightPoints(_ stats: Stats, range: StatsRange) -> [InsightPoint] {
    let days = stats.per_day
    func point(_ chunk: ArraySlice<Stats.Day>) -> InsightPoint {
        var v: [Metric: Int?] = [:]
        for m in Metric.allCases {
            if m.isLine {
                v[m] = chunk.compactMap { $0.value(m) }.last
            } else {
                v[m] = chunk.reduce(0) { $0 + ($1.value(m) ?? 0) }
            }
        }
        return InsightPoint(date: chunk.first!.date, end: chunk.count > 1 ? chunk.last!.date : nil, values: v)
    }
    guard range == .year else { return days.map { point([$0][...]) } }
    return stride(from: 0, to: days.count, by: 7).map { point(days[$0..<min($0 + 7, days.count)]) }
}

/// Mooie schaal: ronde stap (1-2-2,5-5 × 10ⁿ) met hoogstens `maxTicks` stappen.
struct NiceScale {
    let top: Double
    let step: Double
    var ticks: [Double] { stride(from: 0.0, through: top + 0.001, by: step).map { $0 } }

    static func make(_ value: Double, maxTicks: Int = 4) -> NiceScale {
        guard value > 0 else { return NiceScale(top: 4, step: 1) }
        var best: NiceScale?
        var e = 1.0
        while e <= value * 10 {
            for k in [1.0, 2.0, 2.5, 5.0] {
                let step = k * e
                if step.rounded() != step { continue }
                let n = max(1, Int((value / step).rounded(.up)))
                if n > maxTicks || (n < 2 && value > 1) { continue }
                let top = Double(n) * step
                if let b = best, top > b.top || (top == b.top && step <= b.step) { continue }
                best = NiceScale(top: top, step: step)
            }
            e *= 10
        }
        return best ?? NiceScale(top: value.rounded(.up), step: value.rounded(.up))
    }
}

/// Min, max, gemiddeld, laatste en (bij staven) totaal.
struct MetricSummary {
    let cells: [(String, String)]

    init?(_ points: [InsightPoint], _ m: Metric) {
        let v = points.compactMap { $0.values[m] ?? nil }
        guard !v.isEmpty else { return nil }
        let sum = v.reduce(0, +)
        let avg = Double(sum) / Double(v.count)
        var c: [(String, String)] = [("MIN", Fmt.n(v.min()!)), ("MAX", Fmt.n(v.max()!)),
                                     ("GEM.", avg.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "nl_NL")))),
                                     ("LAATSTE", Fmt.n(v.last!))]
        if !m.isLine { c.append(("TOTAAL", Fmt.n(sum))) }
        cells = c
    }
}

/// Eén grafiek in de stijl van Homey Insights: titel met samenvatting, eigen schaal, gedeelde kruisdraad.
struct InsightPanel: View {
    let metric: Metric
    let points: [InsightPoint]
    let range: StatsRange
    @Binding var selection: Date?
    var height: CGFloat = 170

    private var color: Color { Theme.color(metric) }

    private var selected: InsightPoint? {
        guard let selection else { return nil }
        return points.last { $0.date <= selection } ?? points.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom) { title; Spacer(minLength: 12); summary }
                VStack(alignment: .leading, spacing: 6) { title; summary }
            }
            chart.frame(height: height)
        }
    }

    private var title: some View {
        HStack(spacing: 7) {
            Swatch(metric: metric)
            Text(metric.title).font(.subheadline.weight(.semibold))
            Text("· \(metric.detail)\(range == .year ? ", per week" : "")").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
        }
    }

    @ViewBuilder private var summary: some View {
        if let s = MetricSummary(points, metric) {
            HStack(spacing: 14) {
                ForEach(s.cells, id: \.0) { c in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.0).font(.system(size: 9.5, weight: .bold)).kerning(0.5).foregroundStyle(Theme.muted)
                        Text(c.1).font(.system(size: 16, weight: .heavy)).monospacedDigit()
                    }
                }
            }
        }
    }

    private var chart: some View {
        let values = points.compactMap { $0.values[metric] ?? nil }
        let scale = NiceScale.make(Double(values.max() ?? 0) * 1.05)
        let unit: Calendar.Component = range == .year ? .weekOfYear : .day
        let sel = selected
        return Chart {
            ForEach(points) { p in
                if let v = p.values[metric] ?? nil {
                    if metric.isLine {
                        AreaMark(x: .value("Dag", p.date, unit: unit), y: .value(metric.title, v))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.32), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Dag", p.date, unit: unit), y: .value(metric.title, v))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(color)
                    } else {
                        BarMark(x: .value("Dag", p.date, unit: unit), y: .value(metric.title, v),
                                width: .ratio(points.count > 120 ? 0.85 : 0.64))
                            .cornerRadius(points.count > 120 ? 0 : 3)
                            .foregroundStyle(color.opacity(sel == nil || sel?.id == p.id ? 1 : 0.35))
                    }
                }
            }
            if let s = sel {
                RuleMark(x: .value("Dag", s.date, unit: unit))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        tooltip(s)
                    }
                if metric.isLine, let v = s.values[metric] ?? nil {
                    PointMark(x: .value("Dag", s.date, unit: unit), y: .value(metric.title, v))
                        .symbol {
                            Circle().fill(color).frame(width: 11, height: 11)
                                .overlay(Circle().stroke(Theme.card, lineWidth: 2.5))
                        }
                }
            }
        }
        .chartYScale(domain: 0...scale.top)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 5)) { _ in
                AxisTick().foregroundStyle(Color.white.opacity(0.2))
                AxisValueLabel(format: range == .year ? .dateTime.month(.abbreviated)
                    : range == .week ? .dateTime.weekday(.abbreviated).day() : .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: scale.ticks) { v in
                AxisGridLine().foregroundStyle(Color.white.opacity(v.index == 0 ? 0.18 : 0.07))
                AxisValueLabel()
            }
        }
        .overlay {
            if values.isEmpty {
                Text(metric.isLine ? "Nog geen metingen in deze periode" : "Nog geen gegevens")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
        .environment(\.locale, Locale(identifier: "nl_NL"))
        .accessibilityLabel(metric.title)
    }

    private func tooltip(_ p: InsightPoint) -> some View {
        let nl = Locale(identifier: "nl_NL"), utc = TimeZone(identifier: "UTC")!
        let date = p.end == nil
            ? p.date.formatted(Date.FormatStyle(locale: nl, timeZone: utc).weekday(.abbreviated).day().month(.wide))
            : "Week van " + p.date.formatted(Date.FormatStyle(locale: nl, timeZone: utc).day().month(.abbreviated))
        let v = p.values[metric] ?? nil
        return HStack(spacing: 10) {
            Text(date).font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
            Text(v.map(Fmt.n) ?? "geen meting").font(.caption.weight(.heavy)).monospacedDigit()
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Theme.card2.opacity(0.97), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.14)))
        .fixedSize()
    }
}

/// Kleurstaal: rondje (lijn) of blokje (staven).
struct Swatch: View {
    let metric: Metric
    var body: some View {
        Group {
            if metric.isLine { Circle().fill(Theme.color(metric)) } else { RoundedRectangle(cornerRadius: 3).fill(Theme.color(metric)) }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

/// ‹ periode › en Week · Maand · Kwartaal · Jaar.
struct RangeBar: View {
    let stats: Stats?
    @Binding var range: StatsRange
    @Binding var offset: Int
    var showNav = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { nav; Spacer(); picker.frame(maxWidth: 320) }
            VStack(alignment: .leading, spacing: 10) { nav; picker }
        }
    }

    @ViewBuilder private var nav: some View {
        HStack(spacing: 6) {
            if showNav {
                Button { offset += 1 } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                    .disabled(offset >= range.maxOffset)
                    .accessibilityLabel("Vorige periode")
            }
            Text(stats.map { Fmt.period($0.range) } ?? " ")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 150)
                .contentTransition(.numericText())
            if showNav {
                Button { offset -= 1 } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }
                    .disabled(offset == 0)
                    .accessibilityLabel("Volgende periode")
            }
        }
        .buttonStyle(.plain)
    }

    private var picker: some View {
        Picker("Periode", selection: Binding(get: { range }, set: { range = $0; offset = 0 })) {
            ForEach(StatsRange.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
