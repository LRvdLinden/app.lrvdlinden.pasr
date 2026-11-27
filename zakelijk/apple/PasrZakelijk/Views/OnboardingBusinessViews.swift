import SwiftUI

/// Zaak aanmelden (als je nog geen zaak hebt). Daarna kijkt Pasr de aanmelding na.
struct RegisterBusinessView: View {
    var existing: Business? = nil
    var onDone: () -> Void = {}

    @Environment(BusinessStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var city = ""
    @State private var website = ""
    @State private var note = ""
    @State private var busy = false
    @State private var message: String?
    @State private var saved = false
    @State private var showInvite = false
    @State private var inviteCode = ""
    @State private var offerBrand = false
    @State private var brandBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ZakelijkLogo(size: 22)
                        Text(existing == nil ? "Meld je zaak aan" : "Gegevens van je zaak")
                            .font(.title2.weight(.bold))
                        Text("De naam en plaats komen op je stempelkaart. Pasr kijkt je aanmelding na; daarna kun je kaarten publiceren en stempels zetten.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Naam van je zaak", text: $name)
                        .textContentType(.organizationName)
                    TextField("Plaats", text: $city)
                        .textContentType(.addressCity)
                    TextField("Website (bijv. jouwzaak.nl)", text: $website)
                        .keyboard(.url)
                        .textContentType(.URL)
                        .capitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Zaak")
                } footer: {
                    Text("Met je website neemt Pasr je logo en kleuren over op je stempelkaart.")
                }
                Section {
                    TextField("Wat voor zaak is het? (optioneel)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("Je e-mailadres blijft privé.")
                }
                if let message {
                    Section { Text(message).foregroundStyle(Theme.coral) }
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if busy { ProgressView() } else { Text(existing == nil ? "Aanmelden" : "Opslaan").frame(maxWidth: .infinity) }
                    }
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).count < 2)
                }
                if existing == nil {
                    Section {
                        Button("Ik heb een uitnodiging als medewerker") { showInvite = true }
                        Button("Uitloggen", role: .destructive) { Task { await Account.shared.signOut() } }
                    } footer: {
                        Text("Werk je bij een zaak? Open de uitnodigingslink die je van de eigenaar kreeg, of plak de code hier.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                if existing != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .confirmationDialog("Huisstijl opnieuw ophalen?", isPresented: $offerBrand, titleVisibility: .visible) {
                Button("Ophalen en op mijn kaarten zetten") { Task { await applyBrand() } }
                Button("Niet nu", role: .cancel) { dismiss() }
            } message: {
                Text("Je website is gewijzigd. Pasr kan het logo en de kleuren opnieuw ophalen en op je kaarten zetten.")
            }
            .overlay { if brandBusy { ProgressView().controlSize(.large) } }
            .alert("Uitnodiging", isPresented: $showInvite) {
                TextField("Code", text: $inviteCode)
                    .capitalization(.never)
                Button("Verder") {
                    let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = URL(string: code), url.scheme != nil { store.handle(url: url) } else if !code.isEmpty { store.pendingInvite = code }
                    inviteCode = ""
                }
                Button("Annuleer", role: .cancel) { inviteCode = "" }
            } message: {
                Text("Plak de link of de code uit de uitnodiging.")
            }
        }
        .onAppear {
            guard let existing else { return }
            name = existing.name
            city = existing.city
            website = existing.website ?? ""
            note = existing.note ?? ""
        }
    }

    private func save() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await BusinessAPI.register(name: name, city: city, website: website.isEmpty ? nil : website, note: note.isEmpty ? nil : note)
            saved.toggle()
            await store.load()
            onDone()
            if let existing {
                let old = (existing.website ?? "").trimmingCharacters(in: .whitespaces)
                let new = website.trimmingCharacters(in: .whitespaces)
                if !new.isEmpty, new != old, existing.isOwner, !existing.cards.isEmpty { offerBrand = true } else { dismiss() }
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

extension RegisterBusinessView {
    /// Huisstijl van de nieuwe website ophalen en op alle kaarten zetten. Mislukt het, dan blijft alles zoals het was.
    func applyBrand() async {
        guard let business = store.businesses.first(where: { $0.id == existing?.id }) ?? existing else { dismiss(); return }
        brandBusy = true
        defer { brandBusy = false }
        if let brand = await BusinessAPI.brand(business: business.id, url: website.trimmingCharacters(in: .whitespaces)) {
            for var card in business.cards {
                if let logo = brand.logo { card.logo = logo }
                if let color = brand.color { card.color = color }
                card.textColor = brand.textColor
                _ = try? await BusinessAPI.saveCard(card, business: business, logoChanged: brand.logo != nil)
            }
            await store.load()
        }
        dismiss()
    }
}

/// Aanmelding nog niet goedgekeurd (of geblokkeerd).
struct PendingView: View {
    let business: Business
    @Environment(BusinessStore.self) private var store
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: business.status == .blocked ? "hand.raised.fill" : "hourglass")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(business.status == .blocked ? Theme.coral : Theme.amber)
                        .padding(.top, 40)
                        .symbolEffect(.pulse, isActive: business.status == .pending)
                    Text(business.status == .blocked ? "Zaak geblokkeerd" : "Wacht op goedkeuring")
                        .font(.title.weight(.bold))
                    Text(verbatim: business.name + (business.city.isEmpty ? "" : " · " + business.city))
                        .font(.headline).foregroundStyle(.secondary)
                    Text(business.status == .blocked
                         ? "Deze zaak kan Pasr Zakelijk niet meer gebruiken. Neem contact op via pasr.nl/support als je denkt dat dit niet klopt."
                         : "Pasr kijkt je aanmelding zo snel mogelijk na. Je krijgt een mail als je zaak is goedgekeurd. Daarna kun je stempelkaarten publiceren en scannen.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 12) {
                        Button {
                            Task { await store.load() }
                        } label: {
                            if store.loading { ProgressView().tint(.white) } else { Label("Opnieuw kijken", systemImage: "arrow.clockwise") }
                        }
                        .buttonStyle(BigButtonStyle())
                        if business.isOwner && business.status == .pending {
                            Button("Gegevens wijzigen") { editing = true }
                                .font(.headline)
                        }
                        Link(destination: URL(string: "https://pasr.nl/support/")!) {
                            Label("Support", systemImage: "questionmark.circle")
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await store.load() }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                BusinessPicker()
                ToolbarItem(placement: .barTrailing) {
                    Menu {
                        Button("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { await Account.shared.signOut() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Text("Meer"))
                }
            }
        }
        .sheet(isPresented: $editing) {
            RegisterBusinessView(existing: business).trackModal()
        }
    }
}

/// Uitnodiging als medewerker accepteren.
struct InviteAcceptView: View {
    let code: String
    @Environment(BusinessStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var message: String?
    @State private var done = false
    @State private var info: (business: String, city: String)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(Theme.mint)
                    .padding(.top, 30)
                Text("Uitnodiging als medewerker").font(.title2.weight(.bold))
                if let info {
                    Text(verbatim: info.business + (info.city.isEmpty ? "" : " · " + info.city))
                        .font(.headline).foregroundStyle(Theme.iris)
                }
                Text("Je bent uitgenodigd om stempels te zetten voor een zaak. Na het accepteren zie je die zaak in de scanner.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let email = Account.shared.session?.email {
                    Text("Je accepteert met \(email).").font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Text(message).foregroundStyle(Theme.coral).multilineTextAlignment(.center) }
                Button {
                    Task { await accept() }
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text("Accepteren") }
                }
                .buttonStyle(BigButtonStyle(color: Theme.mint, foreground: .black))
                .disabled(busy)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
            }
            .sensoryFeedback(.success, trigger: done)
            .task { info = await BusinessAPI.inviteInfo(code: code) }
        }
    }

    private func accept() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            let businessID = try await BusinessAPI.accept(code: code)
            done = true
            await store.load()
            if let businessID, store.businesses.contains(where: { $0.id == businessID }) { store.select(businessID) }
            store.pendingInvite = nil
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
