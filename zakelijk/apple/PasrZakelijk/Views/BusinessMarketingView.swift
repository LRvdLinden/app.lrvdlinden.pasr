import SwiftUI

/// Zelfde serverfuncties en velden als Pasr Zakelijk Android en het webdashboard.
struct BusinessMarketingView: View {
    let business: Business
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var cardID = ""
    @State private var channel = "social"
    @State private var state = "planned"
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var events: [Event] = []
    @State private var busy = false
    @State private var message: String?

    struct Event: Identifiable {
        let id: String
        let title: String
        let cardName: String
        let starts: String
        let ends: String
        let status: String
        let channel: String
        let details: String
        init?(_ x: [String: Any]) {
            guard let id = x["id"] as? String, let title = x["title"] as? String else { return nil }
            self.id = id; self.title = title
            cardName = x["card_name"] as? String ?? "Algemene actie"
            starts = x["starts_on"] as? String ?? ""
            ends = x["ends_on"] as? String ?? ""
            status = x["status"] as? String ?? "planned"
            channel = x["channel"] as? String ?? "social"
            details = x["details"] as? String ?? ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Campagne plannen") {
                    TextField("Naam van de actie", text: $title)
                    TextField("Omschrijving", text: $details, axis: .vertical).lineLimit(2...4)
                    Picker("Stempelkaart", selection: $cardID) {
                        Text("Algemene actie").tag("")
                        ForEach(business.cards) { card in Text(card.name).tag(card.id) }
                    }
                    DatePicker("Begindatum", selection: $start, displayedComponents: .date)
                    DatePicker("Einddatum", selection: $end, in: start..., displayedComponents: .date)
                    Picker("Kanaal", selection: $channel) {
                        Text("Social media").tag("social")
                        Text("Winkel").tag("winkel")
                        Text("Website").tag("web")
                        Text("E-mail (handmatig)").tag("email")
                    }
                    Picker("Status", selection: $state) {
                        Text("Concept").tag("draft")
                        Text("Gepland").tag("planned")
                        Text("Afgerond").tag("completed")
                    }
                    Button("Campagne opslaan") { Task { await save() } }
                        .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    Text("De kalender plant acties. Er worden geen ongevraagde e-mails of pushberichten verzonden.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Mijn campagnes") {
                    if events.isEmpty { Text("Nog geen campagnes").foregroundStyle(.secondary) }
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.title).font(.headline)
                            Text("\(event.cardName) · \(event.starts) – \(event.ends)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(event.channel) · \(event.status)")
                                .font(.caption).foregroundStyle(.secondary)
                            if !event.details.isEmpty { Text(event.details).font(.subheadline) }
                            Button("Verwijderen", role: .destructive) { Task { await remove(event.id) } }
                                .disabled(busy)
                        }
                    }
                }
                if let message { Section { Text(message).font(.subheadline) } }
            }
            .navigationTitle("Marketingkalender")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { DoneButton() } }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }
    @MainActor private func reload() async {
        do {
            let value = try await Account.shared.rpc("pasr_business_marketing_list", ["p_business": business.id])
            events = (value as? [[String: Any]] ?? []).compactMap(Event.init)
        } catch { message = error.localizedDescription }
    }
    @MainActor private func save() async {
        guard end >= start, title.count <= 100, details.count <= 600 else {
            message = "Controleer titel, omschrijving en datums."; return
        }
        busy = true
        defer { busy = false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        do {
            _ = try await Account.shared.rpc("pasr_business_marketing_save", ["p_event": [
                "business_id": business.id, "card_id": cardID.isEmpty ? NSNull() : cardID,
                "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                "details": details, "channel": channel, "status": state,
                "starts_on": formatter.string(from: start), "ends_on": formatter.string(from: end)
            ] as [String: Any]])
            title = ""; details = ""; message = "Campagne opgeslagen."
            await reload()
        } catch { message = error.localizedDescription }
    }
    @MainActor private func remove(_ id: String) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_marketing_delete", ["p_event": id])
            message = "Campagne verwijderd."
            await reload()
        } catch { message = error.localizedDescription }
    }
}
