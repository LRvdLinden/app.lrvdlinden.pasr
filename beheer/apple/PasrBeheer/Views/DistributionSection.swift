import SwiftUI

/// De verdelingen (tegengehouden aanmeldingen, kaarten per account, landen, delen, platformen). Staan onder Inzichten.
struct DistributionSection: View {
    let stats: Stats?
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { botsCard; perAccountCard; countriesCard; sharingCard }
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) { botsCard; perAccountCard }
                    HStack(alignment: .top, spacing: 16) { countriesCard; sharingCard }
                }
                VStack(spacing: 16) { botsCard; perAccountCard; countriesCard; sharingCard }
            }
            PlatformsCard(days: days)
            Text("Alleen tellingen en accountgegevens, van Pasr op iOS, Android en het web. De inhoud van kaarten staat versleuteld op de server en is hier niet te zien. Dagen in UTC.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

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

    private var sharingCard: some View {
        let sh = stats?.shared ?? Stats.Shared(), tp = stats?.temp ?? Stats.Temp()
        let rows: [(String, Int)] = [
            ("Gedeelde Pasrs", sh.groups), ("Personen in een gedeelde Pasr", sh.people), ("Gedeelde kaarten", sh.cards),
            ("Openstaande uitnodigingen", sh.invites), ("Tijdelijk gedeeld, nu geldig", tp.active),
            ("Tijdelijk: keren geopend (30 dagen)", tp.opens), ("Tijdelijk: eerder gestopt (30 dagen)", tp.revoked_30d),
        ]
        return CardBox {
            VStack(alignment: .leading, spacing: 10) {
                header("Delen", "gedeelde Pasrs en tijdelijk delen")
                if rows.allSatisfy({ $0.1 == 0 }) {
                    Text("Nog niets gedeeld.").font(.subheadline).foregroundStyle(Theme.muted)
                } else {
                    ForEach(rows, id: \.0) { row in
                        HStack {
                            Text(row.0).font(.subheadline)
                            Spacer()
                            Text(Fmt.n(row.1)).font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        Divider().overlay(Theme.line)
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
