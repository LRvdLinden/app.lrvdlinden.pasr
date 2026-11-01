import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt != nil }, sort: \Card.deletedAt, order: .reverse)
    private var deleted: [Card]
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
                Section {
                    LabeledContent("iCloud") {
                        switch iCloudStatus {
                        case .available: Label("Synchroniseert", systemImage: "checkmark.icloud").foregroundStyle(Brand.mint)
                        case .noAccount: Text("Niet ingelogd").foregroundStyle(Brand.coral)
                        case nil: ProgressView()
                        default: Text("Niet beschikbaar").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Kaarten", value: "\(active.count)")
                } footer: {
                    Text("Je kaarten staan op je apparaten en in je eigen iCloud. Pasr heeft geen account en geen server, en verzamelt geen gegevens.")
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
                        Label("Pasr vergrendelen met \(Biometrics.methodName)", systemImage: Biometrics.symbolName)
                    }
                } header: {
                    Text("Beveiliging")
                } footer: {
                    Text("Pasr vraagt \(Biometrics.methodName) bij het openen en als je terugkomt in de app. Losse kaarten kun je ook afschermen: zet dan in de kaart \"Code afschermen\" aan.")
                }

                Section {
                    Toggle("Winkellogo's", isOn: $fetchLogos)
                        .onChange(of: fetchLogos) { _, on in
                            if on {
                                Task { await LogoService.fillMissing(in: context) }
                            } else {
                                LogoService.removeWebsiteLogos(in: context)
                            }
                        }
                } footer: {
                    Text("Bekende winkels hebben hun logo al in Pasr. Voor andere winkels haalt je iPhone het icoon op van de website. Logo's die je zelf hebt uitgeknipt blijven altijd staan.")
                }

                Section {
                    Button { askBackupPassword = true } label: {
                        Label("Maak een back-upbestand", systemImage: "arrow.down.doc")
                    }
                    Button { showImporter = true } label: {
                        Label("Zet een back-up terug", systemImage: "arrow.up.doc")
                    }
                } header: {
                    Text("Back-up")
                } footer: {
                    Text(backupMessage ?? String(localized: "iCloud bewaart je kaarten al. Met een back-upbestand heb je een extra kopie met logo's en foto's, bijvoorbeeld in iCloud Drive, versleuteld met je eigen wachtwoord. Terugzetten voegt alleen kaarten toe die er nog niet zijn."))
                }

                Section("Recent verwijderd") {
                    if deleted.isEmpty {
                        Text("Niets hier. Verwijderde kaarten blijven 30 dagen bewaard.").foregroundStyle(.secondary)
                    }
                    ForEach(deleted) { card in
                        HStack {
                            Circle().fill(Color(hex: card.colorHex)).frame(width: 12, height: 12)
                            Text(card.storeName)
                            Spacer()
                            Button("Zet terug") { card.deletedAt = nil }
                                .buttonStyle(.borderless)
                        }
                        .swipeActions {
                            Button("Nu verwijderen", role: .destructive) { context.delete(card) }
                        }
                    }
                }

                Section {
                    LabeledContent("Versie", value: Bundle.main.versionString)
                    Link("lrvdlinden.app", destination: URL(string: "https://lrvdlinden.app")!)
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

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
