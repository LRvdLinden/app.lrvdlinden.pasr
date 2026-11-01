import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var active: [Card]
    @State private var iCloudStatus: CKAccountStatus?
    @AppStorage(LogoService.settingKey) private var fetchLogos = true
    @AppStorage(Biometrics.appLockKey) private var appLock = false
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

                RemindersSettingsSection()

                Section("Privacy en beveiliging") {
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
                    Text(backupMessage ?? String(localized: "Een extra kopie met logo's en foto's, versleuteld met je eigen wachtwoord."))
                }

                Section("Hulp") {
                    Link(destination: URL(string: "https://pasr.nl/support/")!) {
                        SettingsLabel("Hulp en contact", symbol: "questionmark.circle.fill", color: Brand.iris, external: true)
                    }
                    Link(destination: URL(string: "https://pasr.nl/privacy/")!) {
                        SettingsLabel("Privacyverklaring", symbol: "hand.raised.fill", color: Brand.iris, external: true)
                    }
                    Button {
                        UserDefaults.standard.set(false, forKey: "pasr.onboarded")
                        dismiss()
                    } label: {
                        SettingsLabel("Welkomstscherm opnieuw bekijken", symbol: "sparkles", color: Brand.coral)
                    }
                }

                Section("Ontdekken") {
                    MoreAppsRow()
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
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
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
                    if let doc = try? BackupDocument(backup: PasrBackup(cards: active), password: password) {
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

/// "Meer apps van de maker": naar lrvdlinden.app.
struct MoreAppsRow: View {
    var body: some View {
        Link(destination: URL(string: "https://lrvdlinden.app")!) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [Brand.iris, Brand.coral], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meer apps van Léon").font(.headline).foregroundStyle(.primary)
                    Text("Apps voor iPhone, iPad, Apple TV en Homey").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(spacing: 1) {
                    Text("Bekijk").font(.headline).foregroundStyle(Brand.coral)
                    Text("lrvdlinden.app").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel("Meer apps van Léon op lrvdlinden.app")
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
