import Charts
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var session: Session
    @State private var stats: Stats?
    @State private var error: String?
    @State private var days = 30
    @State private var offset = 0
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
                    HStack(alignment: .top, spacing: 16) { botsCard; perAccountCard; countriesCard }
                    VStack(spacing: 16) {
                        HStack(alignment: .top, spacing: 16) { botsCard; perAccountCard }
                        countriesCard
                    }
                    VStack(spacing: 16) { botsCard; perAccountCard; countriesCard }
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
                KPITile(title: "Landen", value: Fmt.n((stats?.countries ?? [:]).keys.filter { $0 != "?" }.count), detail: "waar accounts vandaan komen", color: Theme.amber)
            }
            .redacted(reason: stats == nil ? .placeholder : [])
        }
    }

    // MARK: grafiek (Accounts en nieuwe accounts, zoals Homey Insights)

    private var chartCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Accounts").font(.headline)
                    Spacer()
                    Button { session.section = .insights } label: {
                        Label("Insights", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered).controlSize(.small)
                }
                RangeBar(stats: stats, range: Binding(get: { StatsRange(rawValue: days) ?? .month }, set: { days = $0.rawValue }),
                         offset: $offset, showNav: false)
                if let stats {
                    let points = insightPoints(stats, range: StatsRange(rawValue: days) ?? .month)
                    InsightPanel(metric: .accounts, points: points, range: StatsRange(rawValue: days) ?? .month, selection: $selected, height: 160)
                    Divider().overlay(Theme.line)
                    InsightPanel(metric: .signups, points: points, range: StatsRange(rawValue: days) ?? .month, selection: $selected, height: 130)
                }
            }
        }
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

    private var countriesCard: some View {
        let entries = (stats?.countries ?? [:]).sorted { ($0.key == "?" ? 1 : 0, -$0.value) < ($1.key == "?" ? 1 : 0, -$1.value) }.prefix(12)
        let total = entries.reduce(0) { $0 + $1.value }, top = entries.map(\.value).max() ?? 0
        return CardBox {
            VStack(alignment: .leading, spacing: 12) {
                header("Landen", "regio van het apparaat")
                if entries.isEmpty {
                    Text("Nog geen accounts.").font(.subheadline).foregroundStyle(Theme.muted)
                } else {
                    ForEach(Array(entries), id: \.key) { e in
                        DistRow(label: "\(Fmt.flag(e.key))  \(Fmt.country(e.key))", value: e.value, total: total, max: top, color: Theme.mint)
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
