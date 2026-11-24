import SwiftUI

/// Gezamenlijke Pasr-winkelstraatacties: ondernemers moeten zelf instemmen.
struct BusinessCommunityView: View {
    let business: Business
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var reward = ""
    @State private var required = 3
    @State private var days = 60
    @State private var memberCode = ""
    @State private var rows: [Campaign] = []
    @State private var busy = false
    @State private var message: String?

    struct Campaign: Identifiable {
        let id: String
        let name: String
        let reward: String
        let required: Int
        let participants: Int
        let joined: Bool
        let lead: String
        init?(_ x: [String: Any]) {
            guard let id = x["id"] as? String, let name = x["name"] as? String else { return nil }
            self.id = id; self.name = name
            reward = x["reward"] as? String ?? ""
            required = (x["required"] as? NSNumber)?.intValue ?? 0
            participants = (x["participants"] as? NSNumber)?.intValue ?? 0
            joined = x["joined"] as? Bool ?? false
            lead = x["lead_business"] as? String ?? ""
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Nieuwe gezamenlijke actie") {
                    TextField("Actienaam", text: $name)
                    TextField("Gezamenlijke beloning", text: $reward)
                    Stepper("Benodigde verschillende winkels: \(required)", value: $required, in: 2...20)
                    Stepper("Looptijd: \(days) dagen", value: $days, in: 1...366)
                    Button("Samenwerking starten") { Task { await create() } }
                        .disabled(busy || name.count < 3 || reward.count < 3)
                    Text("Andere ondernemers beslissen zelf of zij deelnemen. Klantgegevens worden niet tussen ondernemingen gedeeld.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Beschikbare winkelstraatacties") {
                    if rows.isEmpty { Text("Nog geen gezamenlijke acties").foregroundStyle(.secondary) }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.name).font(.headline)
                            Text(row.lead + " · \(row.participants) deelnemende zaken")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Beloning: \(row.reward)")
                            Text("Bezoek \(row.required) verschillende deelnemende winkels")
                                .font(.caption).foregroundStyle(.secondary)
                            if !row.joined {
                                Button("Met mijn onderneming deelnemen") { Task { await join(row.id) } }
                                    .disabled(busy)
                            } else {
                                Label("Je onderneming neemt deel", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                                TextField("Lidcode bij de kassa (PZ…)", text: $memberCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                Button("Gezamenlijke beloning controleren en uitgeven") {
                                    Task { await claim(row.id) }
                                }.disabled(busy || !memberCode.uppercased().hasPrefix("PZ"))
                            }
                        }
                    }
                }
                if let message { Section { Text(message).font(.subheadline) } }
            }
            .navigationTitle("Samenwerkingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
        }
    }
    @MainActor private func load() async {
        do {
            let r = try await Account.shared.rpc("pasr_business_community_list", ["p_business": business.id])
            rows = (r as? [[String: Any]] ?? []).compactMap(Campaign.init)
        } catch { message = error.localizedDescription }
    }
    @MainActor private func create() async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_create", [
                "p_business": business.id, "p_name": name, "p_reward": reward,
                "p_required": required, "p_days": days
            ])
            name = ""; reward = ""; message = "Samenwerking gestart. Andere ondernemingen kunnen nu deelnemen."
            await load()
        } catch { message = error.localizedDescription }
    }
    @MainActor private func join(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_join",
                ["p_business": business.id, "p_campaign": id])
            message = "Je onderneming neemt nu deel."
            await load()
        } catch { message = error.localizedDescription }
    }
    @MainActor private func claim(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            let r = try await Account.shared.rpc("pasr_business_community_claim", [
                "p_business": business.id, "p_campaign": id,
                "p_member_code": memberCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            ])
            let reward = JSONObject(r)?.string("reward") ?? "gezamenlijke beloning"
            message = "Beloning uitgegeven: \(reward). Een tweede inwisseling is niet mogelijk."
            memberCode = ""
        } catch { message = error.localizedDescription }
    }
}
