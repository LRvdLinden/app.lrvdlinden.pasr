import SwiftUI

/// "Mis je een winkel?": naam en website doorgeven. In het beheer wordt de kaart gemaakt en gepubliceerd, zonder
/// app-update; wie hem aanvroeg krijgt dan een melding. Alleen met een Pasr-account (zo kan de melding bij jou komen).
struct StoreRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State var name: String
    @State private var website = ""
    @State private var note = ""
    @State private var notify = true
    @State private var busy = false
    @State private var error: String?
    @State private var sent = false
    @State private var mine: [Request] = []
    @State private var showAccount = false
    private var account: AccountService { .shared }

    struct Request: Identifiable {
        let id: String
        let name: String
        let status: String
        let created: Date?
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: sent ? "checkmark.seal.fill" : "storefront")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(sent ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Brand.gradient))
                            .contentTransition(.symbolEffect(.replace))
                        Text(sent ? "Aanvraag verstuurd" : "Winkel aanvragen").font(.title3.bold())
                        Text(sent
                             ? "Dank je! Zodra de winkel in Pasr staat, krijg je een melding. Een update van de app is niet nodig."
                             : "Geef de naam en de website van de winkel door. Wij maken de kaart met het juiste logo en de juiste kleur.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                if !account.isSignedIn {
                    Section {
                        Button { showAccount = true } label: {
                            SettingsLabel("Inloggen of account maken", symbol: "person.crop.circle.fill.badge.plus", color: Brand.iris)
                        }
                    } footer: {
                        Text("Een winkel aanvragen kan met een gratis Pasr-account, zodat de melding bij jou terechtkomt.")
                    }
                } else if !sent {
                    Section {
                        TextField("Naam van de winkel", text: $name)
                        TextField("Website, bijv. winkel.nl", text: $website)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                        TextField("Opmerking (optioneel)", text: $note, axis: .vertical).lineLimit(1...3)
                    } footer: {
                        Text("Met de website vinden we het logo en de kleuren van de winkel.")
                    }
                    Section {
                        Toggle(isOn: $notify) {
                            SettingsLabel("Melding als hij is toegevoegd", symbol: "bell.badge.fill", color: .red)
                        }
                        Button {
                            Task { await send() }
                        } label: {
                            HStack {
                                Label("Vraag aan", systemImage: "paperplane.fill")
                                Spacer()
                                if busy { ProgressView() }
                            }
                        }
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    } footer: {
                        if let error { Text(error).foregroundStyle(Brand.coral) }
                    }
                }

                if !mine.isEmpty {
                    Section("Je aanvragen") {
                        ForEach(mine) { r in
                            HStack {
                                Text(r.name)
                                Spacer()
                                status(r.status)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Mis je een winkel?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .task { await loadMine() }
            .sheet(isPresented: $showAccount) {
                AccountSheet(mode: .signUp) { Task { await CardSync.sync(in: context); await loadMine() } }
            }
        }
    }

    @ViewBuilder private func status(_ s: String) -> some View {
        switch s {
        case "added": Label("Toegevoegd", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.mint)
        case "rejected": Label("Niet toegevoegd", systemImage: "xmark.circle").foregroundStyle(.secondary)
        default: Label("Aangevraagd", systemImage: "clock").foregroundStyle(.secondary)
        }
    }

    private func send() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            _ = try await account.rpc("pasr_store_request", body: [
                "p_name": name.trimmingCharacters(in: .whitespaces), "p_website": website, "p_note": note,
            ])
            if notify, await UserPush.enable() { await UserPush.sync() }
            withAnimation(.snappy) { sent = true }
            await loadMine()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMine() async {
        guard account.isSignedIn, let rows = try? await account.rpc("pasr_my_store_requests", body: [:]) as? [[String: Any]] else { return }
        let iso = ISO8601DateFormatter()
        mine = rows.prefix(20).compactMap { r in
            guard let id = r["id"] as? String else { return nil }
            return Request(id: id, name: r["name"] as? String ?? "", status: r["status"] as? String ?? "open",
                           created: (r["created_at"] as? String).flatMap { iso.date(from: String($0.prefix(19)) + "Z") })
        }
    }
}
