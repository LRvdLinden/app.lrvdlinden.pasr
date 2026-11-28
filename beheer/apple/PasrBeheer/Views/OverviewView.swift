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
                AttentionCard()
                kpis
                chartCard
            }
            .padding(16)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .navigationTitle("Vandaag")
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
                KPITile(title: "Zakelijke accounts", value: stats?.business_accounts.map { Fmt.n($0) } ?? "–",
                        detail: "geregistreerde zaken", color: Theme.mint)
                KPITile(title: "Bevestigd", value: Fmt.n(t.confirmed), detail: "\(Fmt.n(t.unconfirmed)) wachten nog", color: Theme.mint)
                KPITile(title: "Kaarten in accounts", value: Fmt.n(t.cards), detail: "\(Fmt.plural(t.with_cards, "account", "accounts")) met kaarten", color: Theme.coral)
                KPITile(title: "Actief", value: Fmt.n(t.active_30d), detail: "ingelogd, 30 dagen", color: Theme.iris2)
                KPITile(title: "Apple Wallet-passen", value: Fmt.n(stats?.wallet_total ?? 0), detail: "gemaakt, totaal (Google Wallet: zie iOS en Android)", color: Theme.sky)
                KPITile(title: "Landen", value: Fmt.n((stats?.countries ?? [:]).keys.filter { $0 != "?" }.count), detail: "waar accounts vandaan komen", color: Theme.amber)
                KPITile(title: "Gedeelde Pasrs", value: Fmt.n(stats?.shared?.groups ?? 0),
                        detail: "\(Fmt.plural(stats?.shared?.people ?? 0, "persoon", "personen")) · \(Fmt.plural(stats?.shared?.cards ?? 0, "kaart", "kaarten"))", color: Theme.mint)
                KPITile(title: "Tijdelijk gedeeld", value: Fmt.n(stats?.temp?.active ?? 0),
                        detail: "nu geldig · +\(Fmt.n(stats?.temp?.new_7d ?? 0)) deze week", color: Theme.violet)
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
}

extension Calendar {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
