import SwiftUI

/// Echte vestigingen, niet alleen vrije tekst in kaartinstellingen.
struct BusinessLocationsView: View {
    let business: Business
    @Environment(\.dismiss) private var dismiss
    @State private var locations: [Location] = []
    @State private var name = ""
    @State private var address = ""
    @State private var selectedID: String?
    @State private var active = true
    @State private var busy = false
    @State private var message: String?
    @State private var stats: [String: Int] = [:]

    struct Location: Identifiable {
        let id: String
        let name: String
        let address: String
        let active: Bool
        init?(_ json: [String: Any]) {
            guard let id = json["id"] as? String, let name = json["name"] as? String else { return nil }
            self.id = id; self.name = name
            address = json["address"] as? String ?? ""
            active = json["active"] as? Bool ?? true
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(selectedID == nil ? "Nieuwe vestiging" : "Vestiging bewerken") {
                    TextField("Naam vestiging", text: $name)
                    TextField("Adres", text: $address)
                    Toggle("Actief", isOn: $active)
                    Button(selectedID == nil ? "Vestiging toevoegen" : "Wijzigingen opslaan") {
                        Task { await save() }
                    }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    if selectedID != nil {
                        Button("Bewerken annuleren") { resetForm() }
                    }
                }
                Section("Mijn vestigingen") {
                    if locations.isEmpty { Text("Nog geen vestigingen").foregroundStyle(.secondary) }
                    ForEach(locations) { location in
                        Button {
                            selectedID = location.id
                            name = location.name
                            address = location.address
                            active = location.active
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(location.name).font(.headline)
                                    Spacer()
                                    Text(location.active ? "Actief" : "Inactief")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if !location.address.isEmpty {
                                    Text(location.address).font(.caption).foregroundStyle(.secondary)
                                }
                                Text("Stempels (30 dagen): \(stats[location.id] ?? 0)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if let message { Section { Text(message).font(.subheadline) } }
            }
            .navigationTitle("Vestigingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
        }
    }
    private func resetForm() {
        selectedID = nil; name = ""; address = ""; active = true
    }
    @MainActor private func load() async {
        do {
            let raw = try await Account.shared.rpc("pasr_business_locations_list", ["p_business": business.id])
            locations = (raw as? [[String: Any]] ?? []).compactMap(Location.init)
            if let rawStats = try? await Account.shared.rpc("pasr_business_location_insights", ["p_business": business.id]),
               let rows = rawStats as? [[String: Any]] {
                stats = Dictionary(uniqueKeysWithValues: rows.compactMap { item -> (String, Int)? in
                    guard let id = item["id"] as? String else { return nil }
                    return (id, (item["stamps_30d"] as? NSNumber)?.intValue ?? 0)
                })
            }
        } catch { message = error.localizedDescription }
    }
    @MainActor private func save() async {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              name.count <= 100, address.count <= 200 else {
            message = "Controleer vestigingsnaam en adres."; return
        }
        busy = true
        defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_location_save", [
                "p_business": business.id, "p_name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                "p_address": address.trimmingCharacters(in: .whitespacesAndNewlines),
                "p_id": selectedID as Any? ?? NSNull(), "p_active": active
            ])
            resetForm()
            message = "Vestiging opgeslagen."
            await load()
        } catch { message = error.localizedDescription }
    }
}
