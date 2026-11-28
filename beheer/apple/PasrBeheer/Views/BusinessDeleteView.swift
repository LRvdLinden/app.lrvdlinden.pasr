import SwiftUI

/// Zaak permanent verwijderen (acties business_delete_preview en business_delete, zoals "Verwijderen…" in beheer.pasr.nl).
/// Eerst wat er verdwijnt (aantallen), dan een vinkje en de naam van de zaak overtypen; pas dan wordt de knop actief. De
/// server controleert de naam nog eens. Blokkeren houdt alles, verwijderen haalt de zaak en alles eraan definitief weg.
struct BusinessDeleteCounts: Decodable, Equatable {
    var cards = 0, members = 0, staff = 0, events = 0, upcoming_events = 0, tickets = 0
    var member_cards = 0, member_card_members = 0, campaigns = 0, participations = 0, offers = 0, log = 0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func n(_ k: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: k)) ?? 0 }
        cards = n(.cards); members = n(.members); staff = n(.staff); events = n(.events); upcoming_events = n(.upcoming_events)
        tickets = n(.tickets); member_cards = n(.member_cards); member_card_members = n(.member_card_members)
        campaigns = n(.campaigns); participations = n(.participations); offers = n(.offers); log = n(.log)
    }
    private enum CodingKeys: String, CodingKey {
        case cards, members, staff, events, upcoming_events, tickets, member_cards, member_card_members, campaigns, participations, offers, log
    }

    /// De regels voor het venster; alleen wat er is. Zonder meervoudsvormen, zodat elke regel één vertaling heeft.
    var lines: [String] {
        var out: [String] = []
        if cards > 0 { out.append(String(localized: "Stempelkaarten: \(Fmt.n(cards)), met in totaal \(Fmt.n(members)) leden. De kaart verdwijnt bij de klant bij het volgende verversen in Pasr.")) }
        if staff > 0 { out.append(String(localized: "Medewerkers: \(Fmt.n(staff)) (kunnen niet meer inloggen bij deze zaak)")) }
        if events > 0 { out.append(String(localized: "Events: \(Fmt.n(events)), met \(Fmt.n(tickets)) tickets, inclusief de gegevens van de aanmeldingen")) }
        if member_cards > 0 { out.append(String(localized: "Klantenkaarten: \(Fmt.n(member_cards)), met \(Fmt.n(member_card_members)) leden")) }
        if offers > 0 { out.append(String(localized: "Kortingsbonnen en actiecodes: \(Fmt.n(offers))")) }
        if campaigns > 0 { out.append(String(localized: "Gezamenlijke acties van deze zaak: \(Fmt.n(campaigns)) (worden geannuleerd, deelnemers krijgen geen bericht)")) }
        if participations > 0 { out.append(String(localized: "Deelname aan acties van andere zaken: \(Fmt.n(participations))")) }
        if log > 0 { out.append(String(localized: "Logregels: \(Fmt.n(log))")) }
        return out
    }
}

struct BusinessDeletePreview: Decodable {
    let id: String
    let name: String
    let status: String
    let counts: BusinessDeleteCounts
}

struct BusinessDeleteResult: Decodable {
    let deleted: Bool?
    let name: String?
    let campaigns_cancelled: Int?
}

struct BusinessDeleteView: View {
    let business: Business
    /// Na het verwijderen: de lijst verversen en de details sluiten.
    var onDeleted: () -> Void = {}
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var preview: BusinessDeletePreview?
    @State private var error: String?
    @State private var understood = false
    @State private var typed = ""
    @State private var busy = false

    private var name: String { preview?.name ?? business.name }
    private var canDelete: Bool { preview != nil && understood && typed == name && !busy }
    private var counts: BusinessDeleteCounts { preview?.counts ?? BusinessDeleteCounts() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let preview {
                        Text("\(preview.name) wordt permanent verwijderd, met alles wat eraan hangt. Dit kan niet ongedaan worden gemaakt.")
                            .font(.subheadline)
                        if preview.status == "approved" {
                            Text("De zaak is nu nog goedgekeurd en wordt direct geblokkeerd.").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    } else if error == nil {
                        HStack { ProgressView(); Text("Laden…").foregroundStyle(Theme.muted) }
                    }
                }
                if let preview {
                    Section("Dit verdwijnt") {
                        let lines = preview.counts.lines
                        if lines.isEmpty { Text("De zaak zelf (er hangt verder niets aan)").font(.subheadline) }
                        ForEach(lines, id: \.self) { Text(verbatim: $0).font(.subheadline) }
                    }
                    Section {
                        if counts.upcoming_events > 0 {
                            Label("Aankomende events die nog open staan: \(Fmt.n(counts.upcoming_events)). Aanmelders krijgen geen bericht; annuleer die eerst als je ze wilt laten weten dat het niet doorgaat.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(Theme.coral)
                        }
                        Text("De eigenaar krijgt geen e-mail. Het Pasr-account van de eigenaar en de medewerkers blijft bestaan.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Section {
                        Toggle("Ik begrijp dat dit definitief is en niet ongedaan kan worden gemaakt.", isOn: $understood)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Typ de naam van de zaak om te bevestigen:").font(.footnote).foregroundStyle(Theme.muted)
                            Text(name).font(.subheadline.bold()).textSelection(.enabled)
                            TextField("Naam van de zaak", text: $typed)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                    }
                }
                if let error { Section { Text(error).font(.subheadline).foregroundStyle(Theme.coral) } }
                Section {
                    Button(role: .destructive) { Task { await delete() } } label: {
                        HStack { Text("Definitief verwijderen"); if busy { Spacer(); ProgressView() } }
                    }
                    .disabled(!canDelete)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("\(business.name) verwijderen?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() }.disabled(busy) }
            }
            .interactiveDismissDisabled(busy)
            .task { await load() }
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private func load() async {
        do {
            preview = try await session.call("business_delete_preview", ["id": business.id], as: BusinessDeletePreview.self)
            error = nil
        } catch is CancellationError {
        } catch let e as APIError where e.status == 404 {
            dismiss()
            onDeleted()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() async {
        guard canDelete else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await session.call("business_delete", ["id": business.id, "confirm": typed], as: BusinessDeleteResult.self)
            error = nil
            dismiss()
            onDeleted()
        } catch let e as APIError where e.code == "confirm_mismatch" || e.code == "bad_confirm" {
            error = "De naam klopt niet."
        } catch { self.error = error.localizedDescription }
    }
}
