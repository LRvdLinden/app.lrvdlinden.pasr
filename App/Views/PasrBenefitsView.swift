import SwiftUI
import SwiftData

/// Cadeaukaartbewaker en abonnementen: uitsluitend gegevens van de bestaande Pasr-kaarten.
/// Geen extern saldo uitlezen en geen betalingen verzinnen.
struct PasrBenefitsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var community: [CommunityProgress] = []

    private struct CommunityProgress: Identifiable {
        let id: String
        let name: String
        let reward: String
        let visited: Int
        let required: Int
        let claimed: Bool
        init?(_ row: [String: Any]) {
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
            self.id = id; self.name = name
            reward = row["reward"] as? String ?? ""
            visited = (row["visited"] as? NSNumber)?.intValue ?? 0
            required = (row["required"] as? NSNumber)?.intValue ?? 0
            claimed = row["claimed"] as? Bool ?? false
        }
    }
    @MainActor private func loadCommunity() async {
        guard AccountService.shared.isSignedIn else { return }
        guard let data = try? await AccountService.shared.rpc(
            "pasr_business_community_progress", body: [:]),
            let rows = data as? [[String: Any]] else { return }
        community = rows.compactMap(CommunityProgress.init)
    }

    private var vouchers: [Card] {
        cards.filter { $0.kind == .voucher }.sorted { $0.storeName < $1.storeName }
    }
    private var dated: [Card] {
        cards.filter { $0.expiresAt != nil && ($0.kind == .voucher || $0.kind == .subscription || $0.kind == .code) }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }
    private var total: Double {
        vouchers.filter { ($0.currencyCode ?? "EUR").uppercased() == "EUR" }
            .compactMap(\.balance).reduce(0,+)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Mijn cadeaukaarttegoed", systemImage: "gift.fill")
                            .font(.subheadline.weight(.semibold))
                        Text(total.formatted(.currency(code:"EUR")))
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text("Totaal van de door jou ingevulde eurotegoeden. Pasr leest geen saldi bij uitgevers uit.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 22))

                    Text("Cadeaukaarten").font(.title3.bold())
                    if vouchers.isEmpty {
                        ContentUnavailableView("Geen cadeaukaarten", systemImage: "gift")
                    }
                    ForEach(vouchers) { card in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.storeName).font(.headline)
                                if let expiry = card.expiresAt {
                                    Text("Geldig tot \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(card.isExpired ? Color.red : Color.secondary)
                                } else {
                                    Text("Geen vervaldatum ingevuld")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let balance = card.balance {
                                Text(balance.formatted(.currency(code:card.currencyCode ?? "EUR")))
                                    .font(.subheadline.bold()).monospacedDigit()
                            } else {
                                Text("Saldo onbekend").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 18))
                    }
                    if !community.isEmpty {
                        Text("Gezamenlijke winkelstraatacties").font(.title3.bold())
                        ForEach(community) { item in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(item.name).font(.headline)
                                Text("Bezocht: \(item.visited) van \(item.required) verschillende winkels")
                                    .font(.subheadline)
                                ProgressView(value: Double(item.visited),
                                             total: Double(max(1, item.required)))
                                Text("Beloning: \(item.reward)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if item.claimed {
                                    Label("Beloning al uitgegeven", systemImage: "checkmark.circle.fill")
                                        .font(.caption).foregroundStyle(.green)
                                } else if item.visited >= item.required {
                                    Text("Beloning beschikbaar: laat je Pasr-lidcode bij een deelnemende winkel scannen.")
                                        .font(.caption).foregroundStyle(Brand.mint)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    Text("Verloopt binnenkort").font(.title3.bold())
                    let soon = dated.filter { ($0.expiresAt ?? .distantFuture) < Date.now.addingTimeInterval(60*60*24*45) }
                    if soon.isEmpty {
                        Text("Geen cadeaukaarten, kortingscodes of abonnementen die binnen 45 dagen verlopen.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(soon) { card in
                        HStack(spacing: 12) {
                            Image(systemName: card.kind == .subscription ? "calendar.badge.clock" : "gift")
                                .foregroundStyle(Brand.iris)
                            VStack(alignment: .leading) {
                                Text(card.storeName).font(.headline)
                                if let date = card.expiresAt {
                                    Text(card.isExpired ? "Verlopen" : "Geldig tot \(date.formatted(date: .abbreviated,time: .omitted))")
                                        .font(.footnote)
                                        .foregroundStyle(card.isExpired ? Color.red : Color.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(18)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Mijn voordelen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .task { await loadCommunity() }
        }
    }
}
