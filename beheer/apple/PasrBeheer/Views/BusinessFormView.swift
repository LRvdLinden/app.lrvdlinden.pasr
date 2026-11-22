import SwiftUI

/// Ondernemer aanmaken of bewerken (zakelijk 1.1; zelfde als "Nieuwe ondernemer" en "Bewerken" in beheer.pasr.nl).
/// Een zaak van het beheer is meteen goedgekeurd. E-mail met een Pasr-account = eigenaar; anders een eigenaarslink;
/// leeg = zonder eigenaar (dan beheert het beheer de zaak).
struct BusinessFormView: View {
    let business: Business?
    var onSaved: (Business) -> Void = { _ in }
    var onNewCard: (Business) -> Void = { _ in }
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var city = ""
    @State private var address = ""
    @State private var website = ""
    @State private var email = ""
    @State private var cooldown = 5
    @State private var maxPerScan = 10
    @State private var listed = true
    @State private var send = true
    @State private var saving = false
    @State private var error: String?
    @State private var saved: BusinessSaveResponse?
    @State private var confirmOwner = false

    private var current: Business? { saved?.business ?? business }
    private var hasOwner: Bool { current.map { $0.has_owner != false } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(Theme.coral).font(.subheadline) }
                Section {
                    TextField("Naam van de zaak", text: $name)
                    TextField("Plaats", text: $city)
                    TextField("Adres (optioneel)", text: $address)
                    TextField("Website", text: $website)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Zaak")
                } footer: {
                    Text(current == nil ? "Een zaak die je hier aanmaakt is meteen goedgekeurd." : "Status: \(current?.statusTitle.lowercased() ?? "")")
                }
                Section {
                    TextField(hasOwner ? "E-mail (contact)" : "E-mail van de eigenaar", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    if !hasOwner { Toggle("Eigenaarslink mailen", isOn: $send) }
                } header: {
                    Text("Eigenaar")
                } footer: {
                    Text(hasOwner ? "Deze zaak heeft een eigenaar met een Pasr-account; dit is alleen het contactadres."
                         : "Heeft dit adres al een Pasr-account, dan wordt dat account eigenaar. Anders maken we een eigenaarslink (30 dagen geldig). Leeg = geen eigenaar: dan beheer jij de zaak.")
                }
                Section("Instellingen") {
                    Stepper(value: $cooldown, in: 0...1440, step: cooldown >= 60 ? 15 : 1) {
                        LabeledContent("Afkoeltijd", value: cooldown == 0 ? String(localized: "uit") : "\(cooldown) min")
                    }
                    Stepper(value: $maxPerScan, in: 1...30) {
                        LabeledContent("Max per scan", value: "\(maxPerScan)")
                    }
                    Toggle("Vindbaar in Pasr", isOn: $listed)
                }
                if let r = saved {
                    Section("Opgeslagen") {
                        switch r.owner {
                        case "account":
                            Text("Eigenaar gekoppeld: het Pasr-account met dit e-mailadres is nu eigenaar.")
                        case "invite":
                            if let inv = r.invite {
                                Text(r.mailed == true ? "Eigenaarslink gemaild naar \(inv.email ?? ""). Je kunt hem ook kopiëren of delen."
                                     : "Eigenaarslink gemaakt\(r.mail_ready == false ? " (mailen staat uit: geen SMTP)" : ""). Kopieer of deel hem.")
                                OwnerInviteBlock(invite: inv)
                                if r.unconfirmed_account == true {
                                    Text("Er bestaat al een Pasr-account met dit adres, maar het e-mailadres is niet bevestigd (bijvoorbeeld een review-adres zonder mailbox).")
                                        .font(.footnote).foregroundStyle(Theme.muted)
                                    Button { confirmOwner = true } label: { Label("Account bevestigen en eigenaar maken", systemImage: "checkmark.seal") }
                                }
                            }
                        case "none":
                            Text(r.invite == nil ? "Zonder eigenaar: jij beheert deze zaak. Maak nu de stempelkaart." : "Nog geen eigenaar; de eigenaarslink staat open.")
                        default:
                            Text("Opgeslagen.")
                        }
                        if r.business.allCards.count < 5 {
                            Button { let b = r.business; dismiss(); onNewCard(b) } label: { Label("Nieuwe stempelkaart", systemImage: "plus.rectangle.on.rectangle") }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(current == nil ? "Nieuwe ondernemer" : (current?.name ?? ""))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluiten") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(current == nil ? "Aanmaken" : "Opslaan") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
            .onAppear(perform: fill)
            .confirmationDialog("Account bevestigen en eigenaar maken?", isPresented: $confirmOwner, titleVisibility: .visible) {
                Button("Bevestigen") { Task { await confirmAccount() } }
            } message: {
                Text("Bevestig het e-mailadres alleen als je zeker weet dat het klopt. Het account wordt dan eigenaar van de zaak; het wachtwoord blijft van de gebruiker.")
            }
        }
    }

    private func fill() {
        guard let b = business else { return }
        name = b.name; city = b.city ?? ""; address = b.address ?? ""; website = b.website ?? ""; email = b.email ?? ""
        cooldown = b.cooldown_minutes ?? 5; maxPerScan = b.max_per_scan ?? 10; listed = b.listed ?? true
    }

    /// Onbevestigd account met het adres van de zaak bevestigen en eigenaar maken (business_owner_confirm); nooit wachtwoorden.
    private func confirmAccount() async {
        guard let id = current?.id else { return }
        saving = true
        defer { saving = false }
        do {
            let r = try await session.call("business_owner_confirm", ["id": id], as: BusinessSaveResponse.self)
            saved = r
            error = nil
            onSaved(r.business)
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let t = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var biz: [String: Any] = ["name": t(name), "city": t(city), "website": t(website).isEmpty ? NSNull() : t(website),
                                  "email": t(email), "listed": listed, "cooldown_minutes": cooldown, "max_per_scan": maxPerScan]
        // adres alleen meesturen als het anders is (een nieuw adres wist de oude locatie)
        if current == nil || t(address) != (current?.address ?? "") { biz["address"] = t(address).isEmpty ? NSNull() : t(address) }
        do {
            let r: BusinessSaveResponse
            if let id = current?.id {
                r = try await session.call("business_update", ["id": id, "business": biz, "send": send], as: BusinessSaveResponse.self)
            } else {
                r = try await session.call("business_create", ["business": biz, "send": send], as: BusinessSaveResponse.self)
            }
            saved = r
            error = nil
            onSaved(r.business)
        } catch { self.error = error.localizedDescription }
    }
}

/// Eigenaarslink: QR-code, de link als tekst, kopiëren en delen.
struct OwnerInviteBlock: View {
    let invite: OwnerInvite
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            QRView(text: invite.link, size: 96)
            VStack(alignment: .leading, spacing: 8) {
                Text(invite.link).font(.caption.monospaced()).textSelection(.enabled)
                if let d = DateParse.date(invite.expires_at) {
                    Text("Geldig tot \(d.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "nl_NL"))))")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                HStack {
                    Button(copied ? "Gekopieerd" : "Kopieer link", systemImage: "doc.on.doc") { Clipboard.copy(invite.link); copied = true }
                    if let url = URL(string: invite.link) { ShareLink("Delen", item: url) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
