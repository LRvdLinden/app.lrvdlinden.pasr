import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var active: [Card]
    @Query private var allReceipts: [Receipt]
    @State private var iCloudStatus: CKAccountStatus?
    @AppStorage(LogoService.settingKey) private var fetchLogos = true
    @AppStorage(Biometrics.appLockKey) private var appLock = false
    @AppStorage(ScreenShield.settingKey) private var blockScreenshots = false
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.auto.rawValue
    @AppStorage(CardOrder.key) private var order = CardOrder.az.rawValue
    @State private var exportDoc: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var backupMessage: String?
    @State private var askBackupPassword = false
    @State private var pendingImport: Data?
    @State private var importPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                // Overzicht: hoeveel kaarten en of iCloud bijhoudt
                Section {
                    HStack(spacing: 14) {
                        Image("PasrIcon")
                            .resizable()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(active.count == 1 ? "1 kaart" : "\(active.count) kaarten").font(.headline)
                            iCloudLine.font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }

                AccountSettingsSection()

                if AccountConfig.isConfigured {
                    Section {
                        NavigationLink { SharedPasrView() } label: {
                            HStack {
                                SettingsLabel("Gedeelde Pasr", symbol: "person.2.fill", color: Brand.mint)
                                Spacer()
                                if !GroupService.shared.invites.isEmpty {
                                    Text("\(GroupService.shared.invites.count)")
                                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Brand.coral, in: Capsule())
                                } else if !GroupService.shared.groups.isEmpty {
                                    Text("\(GroupService.shared.groups.count)").foregroundStyle(.secondary)
                                }
                            }
                        }
                        NavigationLink { TempSharesView() } label: {
                            HStack {
                                HStack(spacing: 12) {
                                    FanIcon()
                                    Text("Tijdelijk gedeeld").foregroundStyle(.primary)
                                }
                                Spacer()
                                let active = TempShare.allSent().filter(\.isActive).count
                                if active > 0 { Text("\(active)").foregroundStyle(.secondary) }
                            }
                        }
                    } footer: {
                        Text("Deel kaarten met je gezin of huisgenoten, elk met een eigen account, of leen een kaart tijdelijk uit.")
                    }
                }

                UseSettingsSection()

                RemindersSettingsSection()

                BirthdaySettingsSection()

                Section {
                    Picker(selection: $appearance) {
                        Text("Automatisch").tag(AppAppearance.auto.rawValue)
                        Text("Licht").tag(AppAppearance.light.rawValue)
                        Text("Donker").tag(AppAppearance.dark.rawValue)
                    } label: {
                        SettingsLabel("Weergave", symbol: "circle.lefthalf.filled", color: .gray)
                    }
                    Picker(selection: $order) {
                        ForEach(CardOrder.allCases) { o in Label(o.title, systemImage: o.symbol).tag(o.rawValue) }
                    } label: {
                        SettingsLabel("Volgorde van kaarten", symbol: "arrow.up.arrow.down", color: Brand.iris)
                    }
                    .onChange(of: order) { _, new in
                        Task {
                            if CardOrder(rawValue: new)?.usesLocation == true { _ = await NearbyStores.shared.locationForPin() }
                            WidgetSync.update(with: active)
                        }
                    }
                } footer: {
                    Text("Automatisch volgt de instelling van je iPhone of iPad. Kaarten houden altijd hun eigen kleur. De volgorde is standaard A tot Z; met Meest gebruikt of In de buurt staan die kaarten bovenaan, ook in de widgets en op je Apple Watch. Bij gelijke plaatsen blijft het A tot Z.")
                }

                Section {
                    Toggle(isOn: Binding(get: { appLock }, set: { newValue in
                        // Confirm with Face ID before switching the lock on or off.
                        Task {
                            if await Biometrics.authenticate(reason: String(localized: "Bevestig om de vergrendeling te wijzigen.")) {
                                appLock = newValue
                            }
                        }
                    })) {
                        SettingsLabel("Vergrendelen met \(Biometrics.methodName)", symbol: Biometrics.symbolName, color: Brand.mint)
                    }
                    Toggle(isOn: $blockScreenshots) {
                        SettingsLabel("Screenshots van codes blokkeren", symbol: "eye.slash.fill", color: .indigo)
                    }
                    Toggle(isOn: $fetchLogos) {
                        SettingsLabel("Logo's van websites ophalen", symbol: "photo", color: .orange)
                    }
                    .onChange(of: fetchLogos) { _, on in
                        if on {
                            Task { await LogoService.fillMissing(in: context) }
                        } else {
                            LogoService.removeWebsiteLogos(in: context)
                        }
                    }
                } header: {
                    Text("Privacy en beveiliging")
                } footer: {
                    Text("Met Screenshots van codes blokkeren is de barcode zwart in een screenshot of schermopname. Tijdelijk met jou gedeelde kaarten zijn altijd zo beschermd.")
                }

                Section {
                    Button { askBackupPassword = true } label: {
                        SettingsLabel("Back-up maken", symbol: "arrow.down.doc.fill", color: .blue)
                    }
                    Button { showImporter = true } label: {
                        SettingsLabel("Back-up terugzetten", symbol: "arrow.up.doc.fill", color: .blue)
                    }
                } header: {
                    Text("Back-up")
                } footer: {
                    Text(backupMessage ?? String(localized: "Een extra kopie met logo's, foto's en bonnetjes, versleuteld met je eigen wachtwoord."))
                }

                Section("Hulp") {
                    Link(destination: URL(string: "https://pasr.nl/support/")!) {
                        SettingsLabel("Hulp en contact", symbol: "questionmark.circle.fill", color: Brand.iris, external: true)
                    }
                    Link(destination: URL(string: "https://pasr.nl/privacy/")!) {
                        SettingsLabel("Privacyverklaring", symbol: "hand.raised.fill", color: Brand.iris, external: true)
                    }
                    // opent de App Store (buiten de app) op de pagina om een beoordeling te schrijven
                    Link(destination: URL(string: "https://apps.apple.com/nl/app/id6829229123?action=write-review")!) {
                        SettingsLabel("Beoordeel Pasr", symbol: "star.bubble.fill", color: .orange, external: true)
                    }
                    Button {
                        UserDefaults.standard.set(false, forKey: "pasr.onboarded")
                        dismiss()
                    } label: {
                        SettingsLabel("Welkomstscherm opnieuw bekijken", symbol: "sparkles", color: Brand.coral)
                    }
                }

                Section {
                    MoreAppsCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text(MoreAppsText.current.section)
                }

                Section {
                } footer: {
                    AboutFooter()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Instellingen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar", systemImage: "checkmark") { dismiss() } }
            }
            .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                          defaultFilename: "Pasr-back-up \(Date.now.formatted(.iso8601.year().month().day()))") { result in
                if case .success = result {
                    backupMessage = String(localized: "Back-up opgeslagen met \(active.count) kaarten.")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result, let data = try? BackupDocument.readData(url) else { return }
                if BackupCrypto.isEncrypted(data) {
                    importPassword = ""
                    pendingImport = data
                } else {
                    restore(data, password: nil)
                }
            }
            .sheet(isPresented: $askBackupPassword) {
                BackupPasswordSheet { password in
                    if let doc = try? BackupDocument(backup: PasrBackup(cards: active.filter { !$0.isTemporary }, receipts: allReceipts), password: password) {
                        exportDoc = doc
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            showExporter = true
                        }
                    }
                }
            }
            .alert("Wachtwoord van de back-up", isPresented: Binding(get: { pendingImport != nil },
                                                                   set: { if !$0 { pendingImport = nil } })) {
                SecureField("Wachtwoord", text: $importPassword)
                Button("Annuleer", role: .cancel) { pendingImport = nil }
                Button("Zet terug") {
                    if let data = pendingImport { restore(data, password: importPassword) }
                    pendingImport = nil
                }
            } message: {
                Text("Deze back-up is versleuteld. Vul het wachtwoord in dat je bij het maken hebt gekozen.")
            }
            .task {
                iCloudStatus = try? await CKContainer(identifier: PasrStore.cloudContainer).accountStatus()
            }
        }
    }
}

extension SettingsView {
    @ViewBuilder fileprivate var iCloudLine: some View {
        switch iCloudStatus {
        case .available: Label("Synchroniseert met iCloud", systemImage: "checkmark.icloud").foregroundStyle(Brand.mint)
        case .noAccount: Label("Niet ingelogd bij iCloud", systemImage: "icloud.slash").foregroundStyle(Brand.coral)
        case nil: Text("iCloud controleren…").foregroundStyle(.secondary)
        default: Label("iCloud niet beschikbaar", systemImage: "icloud.slash").foregroundStyle(.secondary)
        }
    }

    fileprivate func restore(_ data: Data, password: String?) {
        do {
            let added = try BackupDocument.decode(data, password: password).restore(into: context)
            backupMessage = String(localized: "\(added) kaarten teruggezet.")
        } catch BackupCrypto.Failure.wrongPassword {
            backupMessage = String(localized: "Het wachtwoord klopt niet. Probeer het opnieuw.")
        } catch {
            backupMessage = String(localized: "Dit bestand is geen Pasr-back-up.")
        }
    }
}

/// Rij zoals in Instellingen van iOS: gekleurd blokje met symbool en de tekst.
struct SettingsLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var external = false

    init(_ title: String, symbol: String, color: Color, external: Bool = false) {
        self.title = title
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
            Text(title).foregroundStyle(.primary)
            if external {
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Onderaan: icoon, versie en build, copyright (zoals Bingr).
struct AboutFooter: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("PasrIcon")
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            Text("Versie: \(Bundle.main.versionString)")
            Text("© \(String(Calendar.current.component(.year, from: .now))) Pasr")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .accessibilityElement(children: .combine)
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Instellingen › Verjaardag: optioneel, alleen dag en maand. Voor het verjaardagsvoordeel van je kaarten.
struct BirthdaySettingsSection: View {
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var enabled = Birthday.value != nil
    @State private var day = Birthday.value?.day ?? 1
    @State private var month = Birthday.value?.month ?? 1

    private static let months: [String] = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nl_NL")
        return f.standaloneMonthSymbols ?? f.monthSymbols ?? []
    }()

    private var maxDay: Int { [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][max(0, min(11, month - 1))] }

    var body: some View {
        let perks = Birthday.cardsWithPerk(cards)
        Section {
            Toggle(isOn: Binding(get: { enabled }, set: { on in
                enabled = on
                save()
            }).animation()) {
                SettingsLabel("Verjaardag", symbol: "birthday.cake.fill", color: Brand.coral)
            }
            if enabled {
                Picker("Dag", selection: Binding(get: { day }, set: { day = $0; save() })) {
                    ForEach(1...maxDay, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Maand", selection: Binding(get: { month }, set: { new in
                    month = new
                    day = min(day, maxDay)
                    save()
                })) {
                    ForEach(1...12, id: \.self) { m in
                        Text(m - 1 < Self.months.count ? Self.months[m - 1] : "\(m)").tag(m)
                    }
                }
            }
        } header: {
            Text("Verjaardagsvoordeel")
        } footer: {
            if enabled && !perks.isEmpty {
                Text("In je verjaardagsmaand krijg je een seintje voor \(Self.names(perks)). Alleen dag en maand, geen jaar; met een Pasr-account staat hij ook in je account.")
            } else {
                Text("Veel winkels geven iets extra in je verjaardagsmaand. Vul je verjaardag in (alleen dag en maand, geen jaar) en Pasr herinnert je eraan voor de kaarten met verjaardagsvoordeel. Met een Pasr-account staat hij ook in je account.")
            }
        }
    }

    private static func names(_ perks: [(card: Card, perk: String)]) -> String {
        let names = perks.prefix(3).map { $0.card.storeName }.joined(separator: ", ")
        return perks.count > 3 ? names + String(localized: " en meer") : names
    }

    private func save() {
        Birthday.set(enabled ? Birthday.Value(day: min(day, maxDay), month: month) : nil, cards: cards)
    }
}
