import SwiftUI

/// Instellingen: zaak (eigenaar), scannen (afkoeltijd, max per scan), vindbaar in Pasr, weergave, account, links,
/// Ontdekken en de app-info.
struct SettingsView: View {
    let business: Business
    @Environment(BusinessStore.self) private var store
    @AppStorage(AppearanceSetting.key) private var appearance: AppearanceSetting = .system
    @State private var cooldown = 5
    @State private var maxPerScan = 10
    @State private var listed = true
    @State private var address = ""
    @State private var dirty = false
    @State private var saving = false
    @State private var message: String?
    @State private var saved = false
    @State private var editingBusiness = false
    @State private var whatsNew = false
    @State private var confirmDelete = false
    @State private var confirmSignOut = false

    static let cooldownOptions = [0, 1, 2, 5, 10, 15, 30, 60, 120, 240, 480, 720, 1440]

    var body: some View {
        NavigationStack {
            Form {
                businessSection
                if business.isOwner {
                    scanSection
                    listingSection
                    if dirty || saving || message != nil {
                        Section {
                            Button {
                                Task { await save() }
                            } label: {
                                if saving { ProgressView().frame(maxWidth: .infinity) } else { Text("Instellingen opslaan").frame(maxWidth: .infinity) }
                            }
                            .disabled(saving || !dirty)
                            if let message { Text(message).font(.footnote).foregroundStyle(message == String(localized: "Opgeslagen") ? Theme.mint : Theme.coral) }
                        }
                    }
                }
                Section("Weergave") {
                    Picker("Weergave", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { Text($0.label).tag($0) }
                    }
                }
                accountSection
                Section {
                    Link(destination: URL(string: "https://pasr.nl/privacy/#stempelkaarten-van-ondernemers")!) {
                        Label("Privacyverklaring", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://pasr.nl/support/")!) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                    Button { whatsNew = true } label: { Label("Wat is nieuw", systemImage: "sparkles") }
                    Link(destination: URL(string: "https://pasr.nl/zakelijk/")!) {
                        Label("Pasr Zakelijk op pasr.nl", systemImage: "safari")
                    }
                }
                Section {
                    MoreAppsCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text(verbatim: MoreAppsText.current.section)
                }
                Section {
                    AppInfoFooter()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Instellingen")
            .toolbar { BusinessPicker() }
            .sensoryFeedback(.success, trigger: saved)
            .onAppear(perform: fill)
            .onChange(of: business) { _, _ in fill() }
            .sheet(isPresented: $editingBusiness) { RegisterBusinessView(existing: business).trackModal() }
            .sheet(isPresented: $whatsNew) { WhatsNewView().trackModal() }
            .confirmationDialog("Account verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Account verwijderen", role: .destructive) {
                    Task {
                        do { try await Account.shared.deleteAccount(); store.reset() } catch { message = error.localizedDescription }
                    }
                }
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text("Je Pasr-account wordt verwijderd, ook in de app Pasr. Ben je eigenaar, dan verdwijnen je zaak, kaarten en leden ook. Dit kan niet ongedaan worden gemaakt.")
            }
            .confirmationDialog("Uitloggen?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Uitloggen", role: .destructive) {
                    Task { await Account.shared.signOut(); store.reset() }
                }
                Button("Annuleer", role: .cancel) {}
            }
        }
    }

    private var businessSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: business.name).font(.headline)
                if !business.city.isEmpty { Text(verbatim: business.city).foregroundStyle(.secondary) }
                Text(business.isOwner ? "Je bent eigenaar" : "Je bent medewerker")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(business.isOwner ? Theme.iris : Theme.mint)
            }
            if business.isOwner {
                Button("Gegevens van de zaak wijzigen", systemImage: "pencil") { editingBusiness = true }
            }
        } header: {
            Text("Zaak")
        }
    }

    private var scanSection: some View {
        Section {
            Picker("Afkoeltijd", selection: $cooldown) {
                ForEach(Self.cooldownOptions, id: \.self) { m in Text(Self.cooldownLabel(m)).tag(m) }
            }
            .onChange(of: cooldown) { _, _ in dirty = true }
            Stepper(value: $maxPerScan, in: 1...30) {
                LabeledContent("Max. stempels per scan") { Text(verbatim: "\(maxPerScan)").monospacedDigit() }
            }
            .onChange(of: maxPerScan) { _, _ in dirty = true }
        } header: {
            Text("Scannen")
        } footer: {
            Text("Afkoeltijd: zo lang moet een klant wachten voor de volgende stempel. Bij scannen kies je zelf het aantal stempels, tot het maximum.")
        }
    }

    private var listingSection: some View {
        Section {
            Toggle("Vindbaar in Pasr", isOn: $listed)
                .onChange(of: listed) { _, _ in dirty = true }
            TextField("Adres (straat, huisnummer, plaats)", text: $address, axis: .vertical)
                .textContentType(.fullStreetAddress)
                .lineLimit(1...3)
                .onChange(of: address) { _, _ in dirty = true }
        } header: {
            Text("Vindbaar in Pasr")
        } footer: {
            Text("Pasr-gebruikers zoeken stempelkaarten in een lijst in de app. Met een adres staat je zaak ook bij \"In de buurt\". Pasr zoekt de plek op via Apple Maps.")
        }
    }

    private var accountSection: some View {
        Section {
            if let email = Account.shared.session?.email {
                LabeledContent("Ingelogd als") { Text(verbatim: email).lineLimit(1) }
            }
            Button("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right") { confirmSignOut = true }
            Button("Account verwijderen", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } header: {
            Text("Account")
        }
    }

    static func cooldownLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: String(localized: "Geen")
        case ..<60: String(format: String(localized: "%lld min"), minutes)
        case 1440: String(localized: "1 dag")
        default: String(format: String(localized: "%lld uur"), minutes / 60)
        }
    }

    private func fill() {
        cooldown = Self.cooldownOptions.min { abs($0 - business.cooldownMinutes) < abs($1 - business.cooldownMinutes) } ?? 5
        maxPerScan = min(30, max(1, business.maxPerScan))
        listed = business.listed
        address = business.address
        // pas na het vullen bijhouden of er iets verandert
        Task { @MainActor in dirty = false }
    }

    private func save() async {
        saving = true
        message = nil
        defer { saving = false }
        var lat = business.lat, lng = business.lng
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            lat = nil
            lng = nil
        } else if trimmed != business.address || lat == nil {
            if let c = await Geocoder.locate(trimmed) {
                lat = c.latitude
                lng = c.longitude
            } else {
                lat = nil
                lng = nil
            }
        }
        do {
            try await BusinessAPI.saveSettings(business: business.id, .init(cooldownMinutes: cooldown, maxPerScan: maxPerScan, listed: listed,
                                                                            address: trimmed, lat: lat, lng: lng))
            saved.toggle()
            await store.load()
            dirty = false
            message = (!trimmed.isEmpty && lat == nil)
                ? String(localized: "Opgeslagen, maar het adres is niet gevonden op de kaart. Controleer het adres.")
                : String(localized: "Opgeslagen")
        } catch {
            message = error.localizedDescription
        }
    }
}
