import SwiftUI

/// Gezamenlijke Pasr-winkelstraatacties: ondernemers moeten zelf instemmen.
/// Eigenaar: actie starten, deelnemen, uitstappen, stoppen (alleen initiatiefnemer) en uitgeven.
/// Medewerker: ziet alleen de acties waaraan de zaak meedoet en kan de beloning uitgeven
/// (bij het scannen verschijnt de beloning ook vanzelf, zie ScanResultSheet).
struct BusinessCommunityView: View {
    let business: Business
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var reward = ""
    @State private var required = 3
    @State private var days = 60
    /// Lidcode per actie, zodat het typen in de ene actie de andere niet vult.
    @State private var memberCodes: [String: String] = [:]
    @State private var rows: [Campaign] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false
    @State private var confirmCancel: Campaign?
    @State private var confirmLeave: Campaign?

    struct Campaign: Identifiable {
        let id: String
        let name: String
        let reward: String
        let required: Int
        let participants: Int
        let participantNames: [String]
        let joined: Bool
        let isLead: Bool
        let lead: String
        let leadCity: String
        let endsAt: Date?
        let claimsHere: Int
        init?(_ x: [String: Any]) {
            guard let j = JSONObject(x), let id = j.string("id"), let name = j.string("name") else { return nil }
            self.id = id; self.name = name
            reward = j.string("reward") ?? ""
            required = j.int("required") ?? 0
            participants = j.int("participants") ?? 0
            participantNames = (x["participant_names"] as? [Any])?.compactMap { $0 as? String } ?? []
            joined = j.bool("joined") ?? false
            isLead = j.bool("is_lead") ?? false
            lead = j.string("lead_business") ?? ""
            leadCity = j.string("lead_city") ?? ""
            endsAt = j.date("ends_at")
            claimsHere = j.int("claims_here") ?? 0
        }
    }

    private var isOwner: Bool { business.isOwner }
    private var nameOK: Bool { (3...80).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count) }
    private var rewardOK: Bool { (3...120).contains(reward.trimmingCharacters(in: .whitespacesAndNewlines).count) }

    var body: some View {
        NavigationStack {
            Form {
                if isOwner {
                    Section {
                        TextField("Actienaam", text: $name)
                        TextField("Gezamenlijke beloning", text: $reward)
                        Stepper("Benodigde verschillende winkels: \(required)", value: $required, in: 2...20)
                        Stepper("Looptijd: \(days) dagen", value: $days, in: 1...366)
                        Button("Samenwerking starten") { Task { await create() } }
                            .disabled(busy || !nameOK || !rewardOK)
                    } header: {
                        Text("Nieuwe gezamenlijke actie")
                    } footer: {
                        Text("Andere ondernemers beslissen zelf of zij deelnemen. Klanten verzamelen een bezoek met een stempel bij elke deelnemende zaak. Klantgegevens worden niet tussen ondernemingen gedeeld.")
                    }
                }
                Section {
                    if !loaded && rows.isEmpty {
                        ProgressView()
                    } else if rows.isEmpty {
                        Text(isOwner ? "Nog geen gezamenlijke acties" : "Je zaak doet nog niet mee aan een gezamenlijke actie")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { row in campaignRow(row) }
                } header: {
                    Text(isOwner ? "Beschikbare winkelstraatacties" : "Acties van je zaak")
                } footer: {
                    Text("Bij het scannen van een klant zie je vanzelf of die een gezamenlijke beloning heeft verdiend.")
                }
                if let message {
                    Section {
                        Label(message, systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(failed ? Theme.coral : Theme.mint)
                    }
                }
            }
            .navigationTitle("Samenwerkingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .confirmationDialog("Actie stoppen?", isPresented: Binding(get: { confirmCancel != nil }, set: { if !$0 { confirmCancel = nil } }),
                                titleVisibility: .visible, presenting: confirmCancel) { row in
                Button("Actie stoppen", role: .destructive) { Task { await cancel(row.id) } }
                Button("Annuleren", role: .cancel) {}
            } message: { _ in
                Text("De actie verdwijnt bij klanten en alle deelnemende zaken. Uitgegeven beloningen blijven geregistreerd.")
            }
            .confirmationDialog("Uitstappen?", isPresented: Binding(get: { confirmLeave != nil }, set: { if !$0 { confirmLeave = nil } }),
                                titleVisibility: .visible, presenting: confirmLeave) { row in
                Button("Uitstappen", role: .destructive) { Task { await leave(row.id) } }
                Button("Annuleren", role: .cancel) {}
            } message: { _ in
                Text("Bezoeken bij jouw zaak tellen daarna niet meer mee voor klanten.")
            }
        }
    }

    @ViewBuilder private func campaignRow(_ row: Campaign) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name).font(.headline)
                Spacer()
                if row.isLead {
                    Text("Initiatiefnemer").font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.mint.opacity(0.18), in: Capsule())
                }
            }
            Text([row.lead, row.leadCity].filter { !$0.isEmpty }.joined(separator: ", ") + " · \(row.participants) deelnemende zaken")
                .font(.caption).foregroundStyle(.secondary)
            if !row.participantNames.isEmpty {
                Text(row.participantNames.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Beloning: \(row.reward)")
            Text("Bezoek \(row.required) verschillende deelnemende winkels")
                .font(.caption).foregroundStyle(.secondary)
            if let end = row.endsAt {
                Text("Loopt tot \(end.formatted(date: .long, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !row.joined {
                if isOwner {
                    Button("Met mijn onderneming deelnemen") { Task { await join(row.id) } }
                        .disabled(busy)
                }
            } else {
                Label(row.claimsHere > 0 ? "Je onderneming neemt deel · \(row.claimsHere)x uitgegeven" : "Je onderneming neemt deel",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                TextField("Lidcode bij de kassa (PZ…)", text: Binding(
                    get: { memberCodes[row.id] ?? "" },
                    set: { memberCodes[row.id] = $0 }))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Gezamenlijke beloning controleren en uitgeven") {
                    Task { await claim(row.id) }
                }
                .disabled(busy || !(memberCodes[row.id] ?? "").trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("PZ"))
                if isOwner {
                    if row.isLead {
                        Button("Actie stoppen", role: .destructive) { confirmCancel = row }.disabled(busy)
                    } else {
                        Button("Uitstappen", role: .destructive) { confirmLeave = row }.disabled(busy)
                    }
                }
            }
        }
        .buttonStyle(.borderless)
    }

    private func show(_ text: String, error: Bool = false) {
        message = text; failed = error
    }

    @MainActor private func load() async {
        do {
            let r = try await Account.shared.rpc("pasr_business_community_list", ["p_business": business.id])
            rows = (r as? [[String: Any]] ?? []).compactMap(Campaign.init)
        } catch { show(error.localizedDescription, error: true) }
        loaded = true
    }
    @MainActor private func create() async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_create", [
                "p_business": business.id,
                "p_name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                "p_reward": reward.trimmingCharacters(in: .whitespacesAndNewlines),
                "p_required": required, "p_days": days
            ])
            name = ""; reward = ""
            show("Samenwerking gestart. Andere ondernemingen kunnen nu deelnemen.")
            await load()
        } catch { show(error.localizedDescription, error: true) }
    }
    @MainActor private func join(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_join",
                ["p_business": business.id, "p_campaign": id])
            show("Je onderneming neemt nu deel.")
            await load()
        } catch { show(error.localizedDescription, error: true) }
    }
    @MainActor private func leave(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_leave",
                ["p_business": business.id, "p_campaign": id])
            show("Je onderneming doet niet meer mee aan deze actie.")
            await load()
        } catch { show(error.localizedDescription, error: true) }
    }
    @MainActor private func cancel(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_cancel",
                ["p_business": business.id, "p_campaign": id])
            show("De actie is gestopt.")
            await load()
        } catch { show(error.localizedDescription, error: true) }
    }
    @MainActor private func claim(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            let r = try await Account.shared.rpc("pasr_business_community_claim", [
                "p_business": business.id, "p_campaign": id,
                "p_member_code": (memberCodes[id] ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            ])
            let reward = JSONObject(r)?.string("reward") ?? "gezamenlijke beloning"
            show("Beloning uitgegeven: \(reward). Een tweede inwisseling is niet mogelijk.")
            memberCodes[id] = nil
            await load()
        } catch { show(error.localizedDescription, error: true) }
    }
}
