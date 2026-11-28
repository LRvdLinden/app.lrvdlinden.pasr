import SwiftUI

/// Zaak permanent verwijderen (acties business_delete_preview en business_delete, zoals "Verwijderen…" in beheer.pasr.nl).
/// Eerst wat er verdwijnt (aantallen), dan een vinkje en de naam van de zaak overtypen; pas dan wordt de knop actief. De
/// server controleert de naam nog eens. Blokkeren houdt alles, verwijderen haalt de zaak en alles eraan definitief weg.
struct BusinessDeleteCounts: Decodable, Equatable {
    var cards = 0, members = 0, staff = 0, events = 0, upcoming_events = 0, tickets = 0
    var member_cards = 0, member_card_members = 0, campaigns = 0, participations = 0, offers = 0, log = 0
    /// Mails aan deelnemers en organisatoren van gezamenlijke acties; en of er een adres van de eigenaar bekend is
    var mail_participants = 0, owner_mail = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func n(_ k: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: k)) ?? 0 }
        cards = n(.cards); members = n(.members); staff = n(.staff); events = n(.events); upcoming_events = n(.upcoming_events)
        tickets = n(.tickets); member_cards = n(.member_cards); member_card_members = n(.member_card_members)
        campaigns = n(.campaigns); participations = n(.participations); offers = n(.offers); log = n(.log)
        mail_participants = n(.mail_participants); owner_mail = (try? c.decodeIfPresent(Bool.self, forKey: .owner_mail)) ?? false
    }
    private enum CodingKeys: String, CodingKey {
        case cards, members, staff, events, upcoming_events, tickets, member_cards, member_card_members, campaigns, participations, offers, log
        case mail_participants, owner_mail
    }

    /// De regels voor het venster; alleen wat er is. Zonder meervoudsvormen, zodat elke regel één vertaling heeft.
    var lines: [String] {
        var out: [String] = []
        if cards > 0 { out.append(String(localized: "Stempelkaarten: \(Fmt.n(cards)), met in totaal \(Fmt.n(members)) leden. De kaart verdwijnt bij de klant bij het volgende verversen in Pasr.")) }
        if staff > 0 { out.append(String(localized: "Medewerkers: \(Fmt.n(staff)) (kunnen niet meer inloggen bij deze zaak)")) }
        if events > 0 { out.append(String(localized: "Events: \(Fmt.n(events)), met \(Fmt.n(tickets)) tickets, inclusief de gegevens van de aanmeldingen")) }
        if member_cards > 0 { out.append(String(localized: "Klantenkaarten: \(Fmt.n(member_cards)), met \(Fmt.n(member_card_members)) leden")) }
        if offers > 0 { out.append(String(localized: "Kortingsbonnen en actiecodes: \(Fmt.n(offers))")) }
        if campaigns > 0 { out.append(String(localized: "Gezamenlijke acties van deze zaak: \(Fmt.n(campaigns)) (worden geannuleerd, de deelnemers krijgen een mail)")) }
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
    struct Mails: Decodable {
        let sent: Int
        let failed: Int
        /// sent, failed, none (geen adres) of off (schakelaar uit)
        let owner: String?
    }
    let deleted: Bool?
    let name: String?
    let campaigns_cancelled: Int?
    let mails: Mails?
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
    @State private var notifyOwner = true
    @State private var result: BusinessDeleteResult?

    private var name: String { preview?.name ?? business.name }
    private var canDelete: Bool { preview != nil && result == nil && understood && typed == name && !busy }
    private var counts: BusinessDeleteCounts { preview?.counts ?? BusinessDeleteCounts() }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Label("\(result.name ?? business.name) is verwijderd.", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                        if let m = result.mails, m.failed > 0 {
                            Text(verbatim: failureText(m))
                                .font(.footnote).foregroundStyle(Theme.coral)
                        }
                    }
                    Section {
                        Button("Sluiten") { dismiss(); onDeleted() }
                    }
                } else {
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
                        Text("Het Pasr-account van de eigenaar en de medewerkers blijft bestaan.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Section {
                        Toggle("Stuur de eigenaar een mail", isOn: $notifyOwner).disabled(!counts.owner_mail)
                        if !counts.owner_mail {
                            Text("Er is geen e-mailadres van de eigenaar bekend: er gaat geen mail naar de eigenaar.").font(.footnote).foregroundStyle(Theme.muted)
                        }
                        if counts.mail_participants > 0 {
                            Text("Aantal deelnemers en organisatoren van gezamenlijke acties dat een mail krijgt: \(Fmt.n(counts.mail_participants)) (de actie is geannuleerd).").font(.footnote).foregroundStyle(Theme.muted)
                        }
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

    /// Wat er van de mails mislukte (aantallen, nooit adressen).
    private func failureText(_ m: BusinessDeleteResult.Mails) -> String {
        var t = String(localized: "\(Fmt.n(m.sent)) van \(Fmt.n(m.sent + m.failed)) mails zijn verstuurd; \(Fmt.n(m.failed)) mislukt.")
        if m.owner == "failed" { t += " " + String(localized: "De mail aan de eigenaar is er ook niet bij.") }
        return t + " " + String(localized: "Verwijderen kan niet worden teruggedraaid; stuur de mislukte berichten zo nodig zelf (Mail › Nieuwe mail).")
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
            let r = try await session.call("business_delete", ["id": business.id, "confirm": typed, "notify_owner": notifyOwner && counts.owner_mail], as: BusinessDeleteResult.self)
            error = nil
            // Zijn alle mails aangekomen, dan terug naar de lijst; anders blijft dit scherm staan met wat mislukte
            if (r.mails?.failed ?? 0) > 0 { result = r } else { dismiss(); onDeleted() }
        } catch let e as APIError where e.code == "confirm_mismatch" || e.code == "bad_confirm" {
            error = "De naam klopt niet."
        } catch { self.error = error.localizedDescription }
    }
}
