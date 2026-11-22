import SwiftUI
import Charts

/// Details van één zaak (zakelijk 1.0): instellingen (afkoeltijd, max per scan, vindbaar in Pasr, adres), stempels per
/// dag, medewerkers (intrekken) en de log. Zelfde als "Details" in beheer.pasr.nl (actie business_detail).
struct BusinessDetailView: View {
    let business: Business
    var onChanged: () -> Void = {}
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var detail: BusinessDetail?
    @State private var error: String?
    @State private var cooldown = 5
    @State private var maxPerScan = 10
    @State private var listed = true
    @State private var address = ""
    @State private var saving = false
    @State private var saved = false
    @State private var revoking: BusinessStaff?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(Theme.coral).font(.subheadline) }
                Section {
                    Stepper(value: $cooldown, in: 0...1440, step: cooldown >= 60 ? 15 : 1) {
                        LabeledContent("Afkoeltijd", value: cooldown == 0 ? "uit" : "\(cooldown) min")
                    }
                    Stepper(value: $maxPerScan, in: 1...30) {
                        LabeledContent("Max per scan", value: "\(maxPerScan)")
                    }
                    Toggle("Vindbaar in Pasr", isOn: $listed)
                    TextField("Adres (optioneel)", text: $address)
                    if let lat = detail?.business.lat, let lng = detail?.business.lng {
                        LabeledContent("Locatie", value: String(format: "%.4f, %.4f", lat, lng))
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Text(saved ? "Opgeslagen" : "Instellingen opslaan")
                            if saving { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(saving || detail == nil)
                } header: {
                    Text("Instellingen")
                } footer: {
                    Text("Vindbaar in Pasr uit = de zaak staat niet meer in Kaart toevoegen › Stempelkaart. De locatie zet de ondernemer met Pasr Zakelijk.")
                }

                if let stats = detail?.stats {
                    Section("Laatste 30 dagen") {
                        Text("\(Fmt.plural(stats.totals.stamps, "stempel", "stempels")) · \(Fmt.plural(stats.totals.rewards, "beloning", "beloningen")) · \(Fmt.plural(stats.totals.new_members, "nieuw lid", "nieuwe leden")) · \(Fmt.plural(stats.totals.members, "lid", "leden")) totaal")
                            .font(.subheadline)
                        Chart(stats.days) { d in
                            BarMark(x: .value("Dag", d.day), y: .value("Stempels", d.stamps))
                                .foregroundStyle(Theme.iris.gradient)
                                .cornerRadius(3)
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 120)
                    }
                }

                if let staff = detail?.staff {
                    Section("Medewerkers") {
                        ForEach(staff) { m in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name.flatMap { $0.isEmpty ? nil : $0 } ?? (m.role == "owner" ? "Eigenaar" : "—")).font(.subheadline.weight(.semibold))
                                    Text([m.email, (m.role == "owner" ? "eigenaar" : "medewerker") + ", " + m.statusTitle].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if m.role != "owner" && m.revoked != true {
                                    Button("Intrekken", role: .destructive) { revoking = m }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                if let log = detail?.log {
                    Section("Log") {
                        if log.isEmpty { Text("Nog niets gebeurd.").foregroundStyle(Theme.muted) }
                        ForEach(log) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(e.title + stand(e)).font(.subheadline).strikethrough(e.undone == true)
                                    Spacer()
                                    Text(Fmt.ago(e.at)).font(.caption).foregroundStyle(Theme.muted)
                                }
                                Text([e.card_name ?? "verwijderde kaart", "…" + (e.member_suffix ?? ""), who(e), e.device].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(business.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar", systemImage: "checkmark") { dismiss() } }
            }
            .refreshable { await load() }
            .task { await load() }
            .confirmationDialog("Medewerker intrekken?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                                titleVisibility: .visible, presenting: revoking) { m in
                Button("Intrekken", role: .destructive) { Task { await revoke(m) } }
            } message: { m in
                Text("\(m.name ?? "Deze medewerker") kan dan niet meer scannen bij \(business.name).")
            }
        }
    }

    private func stand(_ e: BusinessEvent) -> String {
        guard e.kind != "join", e.kind != "claim", let a = e.stamps_before, let b = e.stamps_after else { return "" }
        return " (\(a) → \(b))"
    }

    private func who(_ e: BusinessEvent) -> String {
        if e.by_role == "customer" { return String(localized: "klant") }
        return (e.by_name ?? "?") + (e.by_role == "staff" ? String(localized: " (medewerker)") : "")
    }

    private func load() async {
        do {
            let d = try await session.call("business_detail", ["id": business.id, "limit": 200, "days": 30], as: BusinessDetail.self)
            detail = d
            cooldown = d.business.cooldown_minutes ?? 5
            maxPerScan = d.business.max_per_scan ?? 10
            listed = d.business.listed ?? true
            address = d.business.address ?? ""
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var p: [String: Any] = ["id": business.id, "cooldown_minutes": cooldown, "max_per_scan": maxPerScan, "listed": listed]
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if a != (detail?.business.address ?? "") { p["address"] = a.isEmpty ? NSNull() : a }
        do {
            try await session.call("business_settings", p)
            saved = true
            onChanged()
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func revoke(_ m: BusinessStaff) async {
        do {
            try await session.call("business_staff_revoke", ["id": m.id])
            await load()
            onChanged()
        } catch { self.error = error.localizedDescription }
    }
}
