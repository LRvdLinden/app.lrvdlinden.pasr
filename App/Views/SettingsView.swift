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
                    Toggle("Logo's van winkelwebsites", isOn: $fetchLogos)
                        .onChange(of: fetchLogos) { _, on in
                            if on {
                                Task { await LogoService.fillMissing(in: context) }
                            } else {
                                LogoService.removeWebsiteLogos(in: context)
                            }
                        }
                } footer: {
                    Text("Je iPhone haalt het icoon op dat een winkel zelf op zijn website zet. Pasr levert geen logo's mee. Logo's die je zelf hebt uitgeknipt blijven altijd staan.")
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
            .task {
                iCloudStatus = try? await CKContainer(identifier: PasrStore.cloudContainer).accountStatus()
            }
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
