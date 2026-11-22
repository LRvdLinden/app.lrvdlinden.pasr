import SwiftUI

/// Instellingen: zaak (eigenaar), scannen (afkoeltijd, max per scan), vindbaar in Pasr, account, vergrendeling, weergave, hulp,
/// Ontdekken en de app-info.
struct SettingsView: View {
    let business: Business
    @Environment(BusinessStore.self) private var store
    @AppStorage(AppearanceSetting.key) private var appearance: AppearanceSetting = .system
    @AppStorage(Biometrics.appLockKey) private var appLock = false
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
                accountSection
                securitySection
                Section {
                    Picker(selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { Text($0.label).tag($0) }
                    } label: {
                        SettingsLabel("Weergave", symbol: "circle.lefthalf.filled", color: .gray)
                    }
                } footer: {
                    Text("Automatisch volgt de instelling van je iPhone of iPad.")
                }
                Section("Hulp") {
                    Link(destination: URL(string: "https://pasr.nl/support/")!) {
                        SettingsLabel("Hulp en contact", symbol: "questionmark.circle.fill", color: Theme.iris, external: true)
                    }
                    Link(destination: URL(string: "https://pasr.nl/privacy/#stempelkaarten-van-ondernemers")!) {
                        SettingsLabel("Privacyverklaring", symbol: "hand.raised.fill", color: Theme.iris, external: true)
                    }
                    Button { whatsNew = true } label: {
                        SettingsLabel("Wat is nieuw", symbol: "sparkles", color: Theme.coral)
                    }
                    // pas zichtbaar als AppStoreID.zakelijk is ingevuld (opent de App Store om een beoordeling te schrijven)
                    if let review = AppStoreID.reviewURL {
                        Link(destination: review) {
                            SettingsLabel("Beoordeel Pasr Zakelijk", symbol: "star.bubble.fill", color: .orange, external: true)
                        }
                    }
                    Link(destination: URL(string: "https://pasr.nl/zakelijk/")!) {
                        SettingsLabel("Pasr Zakelijk op pasr.nl", symbol: "safari.fill", color: Theme.mint, external: true)
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
            .busyWhile(confirmDelete || confirmSignOut)
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

    /// Vergrendelen met Face ID (zelfde als Pasr): aan- of uitzetten vraagt eerst om Face ID of de toegangscode.
    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(get: { appLock }, set: { newValue in
                Task {
                    if await Biometrics.authenticate(reason: String(localized: "Bevestig om de vergrendeling te wijzigen.")) {
                        appLock = newValue
                    }
                }
            })) {
                SettingsLabel(String(format: String(localized: "Vergrendelen met %@"), Biometrics.methodName),
                              symbol: Biometrics.symbolName, color: Theme.mint)
            }
            .disabled(!Biometrics.isAvailable)
        } header: {
            Text("Privacy en beveiliging")
        } footer: {
            Text("Bij openen en na terugkeer naar de app vraagt Pasr Zakelijk om Face ID, Touch ID of je toegangscode. Handig als de iPad of iPhone aan de kassa ligt.")
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

/// Regel in Instellingen met een gekleurd icoon (zelfde stijl als Pasr).
struct SettingsLabel: View {
    let title: Text
    let symbol: String
    let color: Color
    var external = false

    init(_ title: LocalizedStringKey, symbol: String, color: Color, external: Bool = false) {
        self.init(text: Text(title), symbol: symbol, color: color, external: external)
    }

    /// Voor een tekst die al vertaald is (bijv. met de naam van Face ID erin).
    @_disfavoredOverload
    init(_ title: String, symbol: String, color: Color, external: Bool = false) {
        self.init(text: Text(verbatim: title), symbol: symbol, color: color, external: external)
    }

    private init(text: Text, symbol: String, color: Color, external: Bool) {
        self.title = text
        self.symbol = symbol
        self.color = color
        self.external = external
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            title.foregroundStyle(.primary)
            if external {
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}
