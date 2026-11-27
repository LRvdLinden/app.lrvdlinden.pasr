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
    @State private var editingCard: BusinessCard?
    @State private var newCard = false
    @State private var editingBusiness = false
    @State private var confirmInvite = false
    @State private var inviteBusy = false
    @State private var confirmOwner = false

    private var biz: Business { detail?.business ?? business }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(Theme.coral).font(.subheadline) }
                Section("Eigenaar") {
                    if biz.has_owner != false {
                        Text(biz.owner_email.map { "\($0) (Pasr-account)" } ?? String(localized: "Pasr-account")).font(.subheadline)
                    } else if let inv = biz.owner_invite {
                        Text(inv.expired == true ? "Nog geen eigenaar; de eigenaarslink voor \(inv.email ?? "—") is verlopen."
                             : "Nog geen eigenaar. Eigenaarslink voor \(inv.email ?? "—"):").font(.subheadline)
                        if inv.expired != true { OwnerInviteBlock(invite: inv) }
                    } else {
                        Text("Geen eigenaar: jij beheert deze zaak. Vul bij Bewerken een e-mailadres in om een eigenaar uit te nodigen.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    if biz.has_owner == false && biz.unconfirmed_account == true {
                        Text("Er bestaat al een Pasr-account met dit adres, maar het e-mailadres is niet bevestigd.").font(.footnote).foregroundStyle(Theme.muted)
                        Button { confirmOwner = true } label: { Label("Account bevestigen en eigenaar maken", systemImage: "checkmark.seal") }
                            .disabled(inviteBusy)
                    }
                    if biz.has_owner == false && (biz.owner_invite != nil || !(biz.email ?? "").isEmpty) {
                        Button {
                            confirmInvite = true
                        } label: {
                            HStack { Text(biz.owner_invite == nil ? "Eigenaarslink maken en mailen" : "Nieuwe link maken en mailen"); if inviteBusy { Spacer(); ProgressView() } }
                        }
                        .disabled(inviteBusy)
                    }
                }

                Section {
                    ForEach(biz.allCards) { c in
                        Button { editingCard = c } label: {
                            HStack(spacing: 10) {
                                LogoTile(hex: c.color, logo: c.logo, name: c.name, key: "biz|\(c.id)|\(c.updated_at ?? "")")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(c.name): \(c.stamps_total) stempels, \(c.reward)").font(.subheadline)
                                    Text("\(c.published == true ? "Online" : "Concept") · \(Fmt.plural(c.members ?? 0, "lid", "leden"))\((c.test_members ?? []).isEmpty ? "" : " · testklant")")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if biz.allCards.count < 5 {
                        Button { newCard = true } label: { Label("Nieuwe stempelkaart", systemImage: "plus.rectangle.on.rectangle") }
                    }
                } header: {
                    Text("Stempelkaarten")
                } footer: {
                    Text("Tik op een kaart om hem te bewerken, de QR-code en flyer te zien of een testklant voor de App Review te maken.")
                }

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

                BusinessOffersSection(businessID: business.id, businessName: business.name)
                BusinessTicketsSection(businessID: business.id, businessName: business.name)

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
                                Text((e.kind == "admin" ? [e.card_name, who(e)] : [e.card_name ?? "verwijderde kaart", "…" + (e.member_suffix ?? ""), who(e), e.device]).compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(biz.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar", systemImage: "checkmark") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Bewerken", systemImage: "pencil") { editingBusiness = true } }
            }
            .sheet(item: $editingCard) { c in
                StampCardEditorView(business: biz, card: c, onChanged: { Task { await load(); onChanged() } }).environmentObject(session)
            }
            .sheet(isPresented: $newCard) {
                StampCardEditorView(business: biz, card: nil, onChanged: { Task { await load(); onChanged() } }).environmentObject(session)
            }
            .sheet(isPresented: $editingBusiness) {
                BusinessFormView(business: biz, onSaved: { _ in Task { await load(); onChanged() } },
                                 onNewCard: { _ in Task { try? await Task.sleep(for: .milliseconds(400)); newCard = true } })
                    .environmentObject(session)
            }
            .confirmationDialog("Account bevestigen en eigenaar maken?", isPresented: $confirmOwner, titleVisibility: .visible) {
                Button("Bevestigen") { Task { await confirmAccount() } }
            } message: {
                Text("Bevestig het e-mailadres alleen als je zeker weet dat het klopt. Het account wordt dan eigenaar van \(biz.name); het wachtwoord blijft van de gebruiker.")
            }
            .confirmationDialog("Eigenaarslink versturen?", isPresented: $confirmInvite, titleVisibility: .visible) {
                Button("Versturen") { Task { await sendInvite() } }
            } message: {
                Text("Een eventuele oude link werkt dan niet meer. De nieuwe gaat naar \(biz.owner_invite?.email ?? biz.email ?? "") en is 30 dagen geldig.")
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
        if e.by_role == "beheer" { return String(localized: "beheer") }
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

    private func confirmAccount() async {
        inviteBusy = true
        defer { inviteBusy = false }
        do {
            _ = try await session.call("business_owner_confirm", ["id": biz.id], as: BusinessSaveResponse.self)
            error = nil
            await load()
            onChanged()
        } catch { self.error = error.localizedDescription }
    }

    private func sendInvite() async {
        inviteBusy = true
        defer { inviteBusy = false }
        do {
            let r = try await session.call("business_owner_invite", ["id": biz.id, "send": true], as: BusinessSaveResponse.self)
            error = r.owner == "account" ? nil : (r.mailed == true ? nil : String(localized: "Nieuwe link gemaakt, maar niet gemaild (geen SMTP). Kopieer hem."))
            await load()
            onChanged()
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

// MARK: - Acties (kortingsbonnen, actiecodes, gezamenlijke acties, vestigingen), zoals in beheer.pasr.nl

struct BusinessOffers: Decodable {
    struct Coupon: Decodable, Identifiable {
        let id: String; let title: String; let discount_type: String; let discount_value: Double
        let ends_at: String; let `public`: Bool?; let deleted_at: String?; let claims: Int?; let redeemed: Int?
    }
    struct PromoCode: Decodable, Identifiable {
        let id: String; let code: String; let title: String; let discount_type: String; let discount_value: Double
        let ends_at: String; let max_uses: Int; let used_count: Int; let active: Bool; let deleted_at: String?
    }
    struct Campaign: Decodable, Identifiable {
        let id: String; let name: String; let reward: String; let lead: Bool; let required_businesses: Int
        let ends_at: String; let cancelled_at: String?; let participants: Int?; let claims: Int?
    }
    struct Location: Decodable, Identifiable { let id: String; let name: String; let address: String?; let active: Bool }
    let coupons: [Coupon]?
    let promo_codes: [PromoCode]?
    let campaigns: [Campaign]?
    let locations: [Location]?
    let referrals: Int?
    let programs: Int?
}

struct BusinessOffersSection: View {
    let businessID: String
    let businessName: String
    @EnvironmentObject private var session: Session
    @State private var offers: BusinessOffers?
    @State private var error: String?
    @State private var pending: (kind: String, id: String, title: String)?

    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return Self.iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    private func ended(_ s: String) -> Bool { (date(s) ?? .distantFuture) < .now }
    private func day(_ s: String) -> String { date(s)?.formatted(date: .abbreviated, time: .omitted) ?? "—" }
    private func disc(_ type: String, _ v: Double) -> String {
        type == "percent" ? "\(Int(v))%" : v.formatted(.currency(code: "EUR"))
    }

    var body: some View {
        Section {
            if let error { Text(error).foregroundStyle(.red) }
            if let o = offers {
                Text("\(o.coupons?.count ?? 0) kortingsbonnen · \(o.promo_codes?.count ?? 0) actiecodes · \(o.campaigns?.count ?? 0) gezamenlijke acties · \(o.locations?.count ?? 0) vestigingen · \(o.programs ?? 0) kaarten met beloningen · \(o.referrals ?? 0) vrienden aangebracht")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(o.coupons ?? []) { c in
                    let off = c.deleted_at != nil || ended(c.ends_at)
                    row("Bon: \(c.title) · \(disc(c.discount_type, c.discount_value))\(c.public == true ? " · voor iedereen" : "")",
                        "\(c.deleted_at != nil ? "verwijderd" : off ? "verlopen" : "actief") · t/m \(day(c.ends_at)) · \(c.claims ?? 0) opgehaald, \(c.redeemed ?? 0) gebruikt",
                        off ? nil : ("coupon", c.id, "Kortingsbon uitzetten"))
                }
                ForEach(o.promo_codes ?? []) { p in
                    let off = p.deleted_at != nil || !p.active || ended(p.ends_at)
                    row("Code \(p.code) · \(p.title) · \(disc(p.discount_type, p.discount_value))",
                        "\(p.deleted_at != nil ? "verwijderd" : !p.active ? "gepauzeerd" : off ? "verlopen" : "actief") · t/m \(day(p.ends_at)) · \(p.used_count)/\(p.max_uses) gebruikt",
                        off ? nil : ("promo_code", p.id, "Actiecode pauzeren"))
                }
                ForEach(o.campaigns ?? []) { m in
                    let off = m.cancelled_at != nil || ended(m.ends_at)
                    row("Samen: \(m.name) · \(m.reward)",
                        "\(m.lead ? "organisator" : "deelnemer") · \(m.cancelled_at != nil ? "geannuleerd" : off ? "afgelopen" : "actief") · \(m.participants ?? 0)/\(m.required_businesses) zaken · \(m.claims ?? 0) beloningen",
                        off || !m.lead ? nil : ("campaign", m.id, "Gezamenlijke actie annuleren"))
                    NavigationLink {
                        CommunityCampaignView(campaignID: m.id, title: m.name, onChanged: { Task { await load() } })
                    } label: {
                        Label("Uitnodigingen en deelnemers", systemImage: "person.2").font(.caption)
                    }
                }
                ForEach(o.locations ?? []) { l in
                    row("Vestiging: \(l.name)", (l.address.flatMap { $0.isEmpty ? nil : $0 } ?? "geen adres") + (l.active ? "" : " · inactief"), nil)
                }
            } else if error == nil {
                ProgressView()
            }
        } header: { Text("Acties") }
        .task { await load() }
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Uitzetten", role: .destructive) {
                if let p = pending { Task { await disable(p.kind, p.id) } }
            }
        } message: {
            Text("Werkt daarna niet meer in Pasr bij \(businessName). De historie blijft bewaard.")
        }
    }

    private func row(_ title: String, _ sub: String, _ action: (String, String, String)?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let action {
                Button("Uitzetten", role: .destructive) { pending = (action.0, action.1, action.2) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func load() async {
        do { offers = try await session.call("business_offers", ["id": businessID], as: BusinessOffers.self); error = nil }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }

    private func disable(_ kind: String, _ id: String) async {
        do { try await session.call("business_offer_disable", ["kind": kind, "id": id]); await load() }
        catch { self.error = error.localizedDescription }
    }
}
