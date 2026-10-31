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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("iCloud") {
                        switch iCloudStatus {
                        case .available: Label("Syncing", systemImage: "checkmark.icloud").foregroundStyle(Brand.mint)
                        case .noAccount: Text("Not signed in").foregroundStyle(Brand.coral)
                        case nil: ProgressView()
                        default: Text("Unavailable").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Cards", value: "\(active.count)")
                } footer: {
                    Text("Your cards are stored on your devices and in your own iCloud. Pasr has no account and no server, and collects no data.")
                }

                Section("Recently deleted") {
                    if deleted.isEmpty {
                        Text("Nothing here. Deleted cards stay for 30 days.").foregroundStyle(.secondary)
                    }
                    ForEach(deleted) { card in
                        HStack {
                            Circle().fill(Color(hex: card.colorHex)).frame(width: 12, height: 12)
                            Text(card.storeName)
                            Spacer()
                            Button("Restore") { card.deletedAt = nil }
                                .buttonStyle(.borderless)
                        }
                        .swipeActions {
                            Button("Delete now", role: .destructive) { context.delete(card) }
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Link("lrvdlinden.app", destination: URL(string: "https://lrvdlinden.app")!)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
