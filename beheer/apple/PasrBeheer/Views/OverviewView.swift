import Charts
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var session: Session
    @State private var stats: Stats?
    @State private var error: String?
    @State private var days = 30
    @State private var offset = 0
    @State private var shown: Set<Series> = [.signups, .confirmed, .wallet]
    @State private var selected: Date?
    @State private var loadedAt: Date?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error {
                    Text(error)
                        .font(.subheadline).foregroundStyle(Theme.coral)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.coral.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                kpis
                chartCard
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { botsCard; perAccountCard }
                    VStack(spacing: 16) { botsCard; perAccountCard }
                }
                Text("Alleen tellingen en accountgegevens. De inhoud van kaarten staat versleuteld op de server en is hier niet te zien. Dagen in UTC.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .navigationTitle("Overzicht")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await load() } } label: { Label("Vernieuwen", systemImage: "arrow.clockwise") }
            }
        }
        .refreshable { await load() }
        .task(id: "\(days)|\(offset)|\(session.refreshTick)") { await load() }
    }

    private func load() async {
        do {
            let s = try await session.call("stats", ["days": days, "offset": offset], as: Stats.self)
            withAnimation(.snappy) { stats = s }
            error = nil
            loadedAt = .now
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: kerncijfers

    private var kpis: some View {
        let t = stats?.totals ?? Stats.Totals()
        return VStack(alignment: .leading, spacing: 8) {
            if let loadedAt {
                Text("Bijgewerkt om \(Fmt.time(loadedAt))").font(.footnote).foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                KPITile(title: "Accounts", value: Fmt.n(t.accounts), detail: "+\(Fmt.n(t.new_7d)) deze week", color: Theme.iris)
                KPITile(title: "Bevestigd", value: Fmt.n(t.confirmed), detail: "\(Fmt.n(t.unconfirmed)) wachten nog", color: Theme.mint)
                KPITile(title: "Kaarten in accounts", value: Fmt.n(t.cards), detail: "\(Fmt.plural(t.with_cards, "account", "accounts")) met kaarten", color: Theme.coral)
                KPITile(title: "Actief", value: Fmt.n(t.active_30d), detail: "ingelogd, 30 dagen", color: Theme.iris2)
                KPITile(title: "Wallet-passen", value: Fmt.n(stats?.wallet_total ?? 0), detail: "gemaakt, totaal", color: Theme.sky)
                KPITile(title: "Nieuw vandaag", value: Fmt.n(t.new_today), detail: "\(Fmt.n(t.new_30d)) in 30 dagen", color: Theme.amber)
            }
            .redacted(reason: stats == nil ? .placeholder : [])
        }
    }

    // MARK: grafiek

    private var rows: [Stats.Day] { stats?.per_day ?? [] }

    private var chartCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack { chartTitle; Spacer(); rangePicker.frame(maxWidth: 320) }
                    VStack(alignment: .leading, spacing: 10) { chartTitle; rangePicker }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Series.allCases) { s in
                            Button {
                                if shown.contains(s) { if shown.count > 1 { shown.remove(s) } } else { shown.insert(s) }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Theme.color(s)).frame(width: 8, height: 8)
                                    Text(s.title).font(.footnote.weight(.semibold))
                                }
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .foregroundStyle(shown.contains(s) ? .primary : Theme.muted)
                                .background(shown.contains(s) ? Theme.color(s).opacity(0.14) : Theme.card2, in: Capsule())
                                .overlay(Capsule().stroke(shown.contains(s) ? Theme.color(s) : Theme.line))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(shown.contains(s) ? .isSelected : [])
                        }
                    }
                }
                chart.frame(height: 240)
                Divider().overlay(Theme.line)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 10) {
                    ForEach(Series.allCases) { s in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Fmt.n(rows.reduce(0) { $0 + $1.value(s) })).font(.title3.bold()).monospacedDigit()
                            Text(s.title).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    private var chartTitle: some View {
        HStack(spacing: 10) {
            Text("Per dag").font(.headline)
            Button { offset += 1 } label: { Image(systemName: "chevron.left") }
                .disabled((offset + 1) * days > 1100)
                .accessibilityLabel("Vorige periode")
            Text(stats.map { Fmt.period($0.range) } ?? " ")
                .font(.footnote).foregroundStyle(Theme.muted).monospacedDigit()
                .frame(minWidth: 140)
            Button { offset -= 1 } label: { Image(systemName: "chevron.right") }
                .disabled(offset == 0)
                .accessibilityLabel("Volgende periode")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var rangePicker: some View {
        Picker("Periode", selection: Binding(get: { days }, set: { days = $0; offset = 0 })) {
            Text("Week").tag(7)
            Text("Maand").tag(30)
            Text("Kwartaal").tag(90)
            Text("Jaar").tag(365)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var chart: some View {
        let active = Series.allCases.filter { shown.contains($0) }
        let unit: Calendar.Component = days == 365 ? .weekOfYear : .day
        return Chart {
            ForEach(rows) { d in
                ForEach(active) { s in
                    BarMark(x: .value("Dag", d.date, unit: unit), y: .value(s.title, d.value(s)))
                        .foregroundStyle(by: .value("Reeks", s.title))
                        .cornerRadius(3)
                }
            }
            if let selected, let d = rows.first(where: { Calendar.utc.isDate($0.date, inSameDayAs: selected) }) {
                RuleMark(x: .value("Dag", d.date, unit: .day))
                    .foregroundStyle(Color.white.opacity(0.15))
                    .annotation(position: .top, alignment: .center, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(d)
                    }
            }
        }
        .chartForegroundStyleScale(domain: Series.allCases.map(\.title), range: Series.allCases.map(Theme.color))
        .chartLegend(.hidden)
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: days == 7 ? 7 : 6)) { _ in
                AxisGridLine().foregroundStyle(Theme.line.opacity(0.5))
                AxisValueLabel(format: days == 365 ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel()
            }
        }
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
        .environment(\.locale, Locale(identifier: "nl_NL"))
    }

    private func tooltip(_ d: Stats.Day) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(d.date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "nl_NL"), timeZone: TimeZone(identifier: "UTC")!)))
                .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
            ForEach(Series.allCases) { s in
                HStack {
                    Circle().fill(Theme.color(s)).frame(width: 7, height: 7)
                    Text(s.title)
                    Spacer(minLength: 12)
                    Text(Fmt.n(d.value(s))).monospacedDigit().fontWeight(.semibold)
                }
                .font(.caption)
            }
        }
        .padding(9)
        .frame(width: 180)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }

    // MARK: verdelingen

    private static let reasons = ["honeypot": "Honeypot ingevuld", "too_fast": "Te snel ingevuld", "rate_limit": "Te veel vanaf één netwerk",
                                  "disposable": "Wegwerpadres", "other": "Overig"]

    private var botsCard: some View {
        let entries = (stats?.bots_7d ?? [:]).sorted { $0.value > $1.value }
        let total = entries.reduce(0) { $0 + $1.value }, top = entries.first?.value ?? 0
        return CardBox {
            VStack(alignment: .leading, spacing: 12) {
                header("Tegengehouden aanmeldingen", "laatste 7 dagen")
                if entries.isEmpty {
                    Text("Geen bots deze week. \(Fmt.plural(stats?.signups_allowed_7d ?? 0, "gewone aanmelding", "gewone aanmeldingen")).")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                } else {
                    ForEach(entries, id: \.key) { e in
                        DistRow(label: Self.reasons[e.key] ?? e.key, value: e.value, total: total, max: top, color: Theme.amber)
                    }
                }
            }
        }
    }

    private var perAccountCard: some View {
        let order = ["0", "1-5", "6-15", "16-30", "31+"]
        let c = stats?.cards_per_account ?? [:]
        let entries = order.compactMap { k in c[k].map { (k, $0) } }
        let total = entries.reduce(0) { $0 + $1.1 }, top = entries.map(\.1).max() ?? 0
        return CardBox {
            VStack(alignment: .leading, spacing: 12) {
                header("Kaarten per account", "alle accounts")
                if entries.isEmpty {
                    Text("Nog geen accounts.").font(.subheadline).foregroundStyle(Theme.muted)
                } else {
                    ForEach(entries, id: \.0) { e in
                        DistRow(label: e.0 == "0" ? "Nog geen kaarten" : "\(e.0) kaarten", value: e.1, total: total, max: top, color: Theme.iris)
                    }
                }
            }
        }
    }

    private func header(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

extension Calendar {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
