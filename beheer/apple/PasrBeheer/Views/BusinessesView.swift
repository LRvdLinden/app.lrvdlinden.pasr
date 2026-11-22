import SwiftUI

/// Ondernemers (Pasr voor ondernemers, pasr.nl/zakelijk): aanmeldingen goedkeuren of blokkeren en hun stempelkaarten zien.
struct BusinessesView: View {
    @EnvironmentObject private var session: Session
    @State private var businesses: [Business] = []
    @State private var filter = "pending"
    @State private var loading = false
    @State private var error: String?
    @State private var blocking: Business?

    private static let filters = [("pending", "Wacht"), ("approved", "Goedgekeurd"), ("blocked", "Geblokkeerd"), ("all", "Alle")]
    private var shown: [Business] { filter == "all" ? businesses : businesses.filter { $0.status == filter } }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Self.filters, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if let error { Text(error).foregroundStyle(Theme.coral).font(.subheadline) }
            Section {
                ForEach(shown) { b in
                    BusinessRow(business: b)
                        .swipeActions(edge: .trailing) {
                            if b.status != "approved" {
                                Button { Task { await set(b, "approved") } } label: { Label("Goedkeuren", systemImage: "checkmark") }.tint(Theme.mint)
                            }
                            if b.status != "blocked" {
                                Button(role: .destructive) { blocking = b } label: { Label("Blokkeren", systemImage: "hand.raised") }
                            }
                        }
                        .contextMenu {
                            if b.status != "approved" { Button { Task { await set(b, "approved") } } label: { Label("Goedkeuren", systemImage: "checkmark.circle") } }
                            if b.status != "blocked" { Button(role: .destructive) { blocking = b } label: { Label("Blokkeren", systemImage: "hand.raised") } }
                            if b.status == "blocked" { Button { Task { await set(b, "pending") } } label: { Label("Terug naar wachten", systemImage: "clock") } }
                        }
                }
            } header: {
                Text("\(Fmt.plural(businesses.count, "zaak", "zaken")), \(Fmt.n(businesses.filter { $0.status == "pending" }.count)) wachten")
            }
            if !loading && shown.isEmpty && error == nil {
                ContentUnavailableView(filter == "pending" ? "Geen aanmeldingen die wachten" : "Geen zaken", systemImage: "storefront")
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Ondernemers")
        .refreshable { await load() }
        .task(id: session.refreshTick) { await load() }
        .confirmationDialog("Zaak blokkeren?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
                            titleVisibility: .visible, presenting: blocking) { b in
            Button("Blokkeer \(b.name)", role: .destructive) { Task { await set(b, "blocked") } }
        } message: { _ in
            Text("De zaak kan niet meer scannen en de kaarten gaan offline. Leden zien dat de kaart niet meer actief is.")
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            businesses = try await session.call("businesses", as: BusinessesResponse.self).businesses
            error = nil
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch { self.error = error.localizedDescription }
    }

    private func set(_ b: Business, _ status: String) async {
        do {
            try await session.call("business_status", ["id": b.id, "status": status])
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

private struct BusinessRow: View {
    let business: Business

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(business.name + (business.city.map { $0.isEmpty ? "" : " · " + $0 } ?? "")).font(.headline)
                Spacer()
                Text(business.statusTitle)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .foregroundStyle(business.status == "approved" ? Theme.mint : business.status == "blocked" ? Theme.coral : Theme.amber)
                    .background((business.status == "approved" ? Theme.mint : business.status == "blocked" ? Theme.coral : Theme.amber).opacity(0.14), in: Capsule())
            }
            Text([business.email, business.website, "aangemeld " + Fmt.ago(business.created_at)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.muted)
            if let note = business.note, !note.isEmpty { Text(note).font(.subheadline) }
            ForEach(business.cards) { c in
                HStack(spacing: 10) {
                    LogoTile(hex: c.color, logo: c.logo, name: c.name, key: "biz|\(c.id)|\(c.updated_at ?? "")")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(c.name): \(c.stamps_total) stempels, \(c.reward)").font(.subheadline)
                        Text("\(c.published == true ? "Online" : "Concept") · \(Fmt.plural(c.members ?? 0, "lid", "leden")) · \(Fmt.plural(c.stamps ?? 0, "stempel", "stempels")) · \(Fmt.plural(c.rewards ?? 0, "beloning", "beloningen"))")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
