import SwiftUI

/// Overzicht: tegels voor komende events (aanmeldingen) en aflopende kortingsperiodes van klantenkaarten.
struct TKOverviewSection: View {
    let events: [TicketEvent]
    let cards: [MemberCard]

    private var upcoming: [TicketEvent] {
        Array(events.filter { !$0.isCancelled && $0.endsAt > .now }.prefix(3))
    }

    /// Kortingen die nu gelden en binnen 7 dagen aflopen.
    private struct Ending: Identifiable {
        let card: MemberCard
        let discount: DiscountInfo
        var id: String { card.id }
    }

    private var ending: [Ending] {
        cards.compactMap { card in
            guard let d = card.discountNow, let until = d.until, until.timeIntervalSinceNow < 7 * 86_400 else { return nil }
            return Ending(card: card, discount: d)
        }
    }

    private var members: Int { cards.reduce(0) { $0 + $1.members } }

    var body: some View {
        Group {
            if !upcoming.isEmpty {
                Section("Komende events") {
                    ForEach(upcoming) { event in
                        HStack(spacing: 12) {
                            VStack(spacing: 0) {
                                Text(verbatim: event.startsAt.formatted(.dateTime.day())).font(.title3.weight(.heavy))
                                Text(verbatim: event.startsAt.formatted(.dateTime.month(.abbreviated)).uppercased()).font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: event.name).font(.body.weight(.semibold)).lineLimit(1)
                                Text(String(format: String(localized: "%@ · %lld/%lld aangemeld"),
                                            event.startsAt.formatted(date: .omitted, time: .shortened), event.registered, event.capacity))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                ProgressView(value: Double(min(event.registered, max(1, event.capacity))), total: Double(max(1, event.capacity)))
                                    .tint(Theme.iris)
                            }
                            TKStatusPill(status: event.status)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !cards.isEmpty {
                Section("Klantenkaarten") {
                    LabeledContent("Klantenkaart-leden") { Text(verbatim: "\(members)").monospacedDigit() }
                    ForEach(ending) { item in
                        let card = item.card
                        let d = item.discount
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: String(localized: "Kortingsperiode %@%% bij %@"), TKFormat.percent(d.percent), card.name))
                                    .font(.body.weight(.semibold))
                                if let until = d.until {
                                    Text(String(format: String(localized: "Loopt af op %@"), until.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))))
                                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.coral)
                                }
                            }
                        } icon: { Image(systemName: "percent").foregroundStyle(Theme.coral) }
                    }
                    ForEach(cards.filter { $0.status == "draft" }) { card in
                        Label {
                            Text(String(format: String(localized: "%@ staat nog in concept"), card.name))
                        } icon: { Image(systemName: "pencil.circle").foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}
