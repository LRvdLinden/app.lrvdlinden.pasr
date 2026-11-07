import SwiftUI
import SwiftData

/// Instellingen › Gedeelde Pasr: je gedeelde Pasrs, uitnodigingen voor jou en een nieuwe maken.
struct SharedPasrView: View {
    @Environment(\.modelContext) private var context
    @State private var showAccount = false
    @State private var askName = false
    @State private var newName = ""
    @State private var busy = false
    @State private var error: String?
    private var groups: GroupService { .shared }
    private var account: AccountService { .shared }

    var body: some View {
        Form {
            header
            if !account.isSignedIn {
                Section {
                    Button { showAccount = true } label: {
                        SettingsLabel("Inloggen of account maken", symbol: "person.crop.circle.fill.badge.plus", color: Brand.iris)
                    }
                } footer: {
                    Text("Voor een gedeelde Pasr heeft iedereen een gratis Pasr-account nodig. Uitgenodigd? Maak je account met het e-mailadres waarop je de uitnodiging kreeg.")
                }
            } else {
                if !groups.invites.isEmpty {
                    Section("Uitnodigingen voor jou") {
                        ForEach(groups.invites) { invite in
                            InviteRow(invite: invite) { accept in
                                Task { await respond(invite, accept) }
                            }
                        }
                    }
                }
                Section {
                    ForEach(groups.groups) { group in
                        NavigationLink {
                            GroupDetailView(groupID: group.id)
                        } label: {
                            HStack(spacing: 12) {
                                GroupBadge()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name).foregroundStyle(.primary)
                                    Text(summary(group)).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if groups.canCreate {
                        Button {
                            newName = groups.groups.isEmpty ? String(localized: "Gezin") : ""
                            askName = true
                        } label: {
                            HStack {
                                SettingsLabel("Nieuwe gedeelde Pasr", symbol: "plus", color: Brand.mint)
                                Spacer()
                                if busy { ProgressView() }
                            }
                        }
                        .disabled(busy)
                    }
                } header: {
                    Text("Jouw gedeelde Pasrs")
                } footer: {
                    Text(error ?? String(localized: "Maximaal \(groups.maxGroups) gedeelde Pasrs, elk met maximaal \(groups.maxMembers) personen. Iedereen in een gedeelde Pasr mag kaarten toevoegen, wijzigen en verwijderen en anderen uitnodigen."))
                        .foregroundStyle(error == nil ? Color.secondary : Brand.coral)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Brand.ink.ignoresSafeArea())
        .navigationTitle("Gedeelde Pasr")
        .refreshable { await groups.sync(in: context) }
        .task { if account.isSignedIn { await groups.refresh() } }
        .sheet(isPresented: $showAccount) {
            AccountSheet(mode: .signUp) { Task { await CardSync.sync(in: context) } }
        }
        .alert("Nieuwe gedeelde Pasr", isPresented: $askName) {
            TextField("Naam, bijv. Gezin", text: $newName)
            Button("Annuleer", role: .cancel) {}
            Button("Maak") { Task { await create() } }
        } message: {
            Text("Daarna nodig je anderen uit met hun e-mailadres.")
        }
    }

    private var header: some View {
        Section {
            VStack(spacing: 14) {
                SharedStackArt()
                    .frame(height: 96)
                Text("Kaarten samen gebruiken").font(.title3.bold())
                Text("Deel klantenkaarten met je gezin of huisgenoten. Iedereen houdt zijn eigen account en privékaarten; de kaarten in de gedeelde Pasr zien jullie allemaal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    private func summary(_ group: GroupService.Group) -> String {
        let people = group.members.count == 1 ? String(localized: "1 persoon") : String(localized: "\(group.members.count) personen")
        let cards = group.cards == 1 ? String(localized: "1 kaart") : String(localized: "\(group.cards) kaarten")
        return "\(people) · \(cards)"
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        busy = true
        defer { busy = false }
        do { try await groups.create(name: name); error = nil } catch { self.error = error.localizedDescription }
    }

    private func respond(_ invite: GroupService.Invite, _ accept: Bool) async {
        do { try await groups.respond(invite, accept: accept, in: context); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

/// Eén gedeelde Pasr: naam, leden, openstaande uitnodigingen, iemand uitnodigen en verlaten.
struct GroupDetailView: View {
    let groupID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var busy = false
    @State private var message: String?
    @State private var error: String?
    @State private var renaming = false
    @State private var newName = ""
    @State private var removing: GroupService.Member?
    @State private var confirmLeave = false
    @FocusState private var emailFocused: Bool
    private var groups: GroupService { .shared }

    var body: some View {
        Form {
            if let group = groups.group(groupID) {
                Section {
                    Button { newName = group.name; renaming = true } label: {
                        LabeledContent("Naam") { Text(group.name).foregroundStyle(.secondary) }
                    }
                    .foregroundStyle(.primary)
                    LabeledContent("Kaarten", value: "\(group.cards)")
                }

                Section {
                    ForEach(group.members) { member in
                        HStack(spacing: 12) {
                            Avatar(text: member.displayName)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.isMe ? String(localized: "\(member.displayName) (jij)") : member.displayName)
                                if member.firstName?.isEmpty == false {
                                    Text(member.email).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if member.isCreator {
                                Text("Maker").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            if !member.isMe {
                                Button("Verwijder", role: .destructive) { removing = member }
                            }
                        }
                    }
                    ForEach(group.invites) { invite in
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.badge")
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.08), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invite.email)
                                Text("Uitgenodigd").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Intrekken", role: .destructive) { Task { await run { try await groups.cancelInvite(invite.id) } } }
                        }
                    }
                } header: {
                    Text("Personen (\(group.seatsUsed) van \(groups.maxMembers))")
                } footer: {
                    Text("Veeg naar links om iemand te verwijderen of een uitnodiging in te trekken.")
                }

                if group.seatsUsed < groups.maxMembers {
                    Section {
                        TextField("E-mailadres", text: $email)
                            .focused($emailFocused)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .textContentType(.emailAddress)
                            #endif
                            .onSubmit { Task { await invite() } }
                        Button { Task { await invite() } } label: {
                            HStack {
                                Label("Stuur uitnodiging", systemImage: "paperplane.fill")
                                Spacer()
                                if busy { ProgressView() }
                            }
                        }
                        .disabled(busy || !email.contains("@"))
                    } header: {
                        Text("Iemand uitnodigen")
                    } footer: {
                        Text(error ?? message ?? String(localized: "Gebruik het e-mailadres waarmee de ander inlogt in Pasr. Nog geen account? Dan maakt die er een met dit adres en accepteert daarna de uitnodiging."))
                            .foregroundStyle(error == nil ? Color.secondary : Brand.coral)
                    }
                }

                Section {
                    Button("Gedeelde Pasr verlaten", role: .destructive) { confirmLeave = true }
                } footer: {
                    Text(group.members.count == 1
                         ? String(localized: "Je bent de enige: verlaat je de gedeelde Pasr, dan verdwijnt hij met alle kaarten erin.")
                         : String(localized: "De anderen houden de gedeelde kaarten."))
                }
            } else {
                Section { Text("Deze gedeelde Pasr bestaat niet meer.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Brand.ink.ignoresSafeArea())
        .navigationTitle(groups.group(groupID)?.name ?? String(localized: "Gedeelde Pasr"))
        .refreshable { await groups.refresh() }
        .alert("Naam wijzigen", isPresented: $renaming) {
            TextField("Naam", text: $newName)
            Button("Annuleer", role: .cancel) {}
            Button("Bewaar") { Task { await run { try await groups.rename(groupID, to: newName) } } }
        }
        .confirmationDialog(Text("\(removing?.displayName ?? "") verwijderen?"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Verwijder", role: .destructive) {
                if let member = removing { Task { await run { try await groups.remove(member, from: groupID, in: context) } } }
                removing = nil
            }
        } message: {
            Text("De gedeelde kaarten verdwijnen van de apparaten van deze persoon. Je kunt diegene later opnieuw uitnodigen.")
        }
        .confirmationDialog("Gedeelde Pasr verlaten?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Verlaat en bewaar kopieën als privé") { leave(keepCopies: true) }
            Button("Verlaat", role: .destructive) { leave(keepCopies: false) }
        } message: {
            Text("De kaarten van deze gedeelde Pasr verdwijnen van je apparaten, tenzij je een privékopie bewaart.")
        }
    }

    private func leave(keepCopies: Bool) {
        Task {
            await run { try await groups.remove(nil, from: groupID, keepCopies: keepCopies, in: context) }
            if error == nil { dismiss() }
        }
    }

    private func invite() async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let mailed = try await groups.invite(address, to: groupID)
            message = mailed
                ? String(localized: "Uitnodiging verstuurd naar \(address).")
                : String(localized: "Uitnodiging klaar. Laat \(address) inloggen in Pasr met dit adres; de uitnodiging staat daar klaar.")
            error = nil
            email = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run(_ work: () async throws -> Void) async {
        do { try await work(); error = nil } catch { self.error = error.localizedDescription }
    }
}

/// "Léon nodigt je uit voor Gezin": accepteren, weigeren of later.
struct GroupInviteSheet: View {
    let invite: GroupService.Invite
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 10)
            SharedStackArt()
                .frame(height: 120)
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)
            VStack(spacing: 8) {
                Text("\(invite.from) nodigt je uit").font(.title2.bold()).multilineTextAlignment(.center)
                Text("voor de gedeelde Pasr **\(invite.groupName)**").font(.headline).foregroundStyle(.secondary)
                Text("Kaarten in een gedeelde Pasr zien en gebruiken jullie allemaal. Je privékaarten blijven van jou.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 4)
            }
            .padding(.horizontal, 28)
            if let error {
                Text(error).font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center).padding(.horizontal)
            }
            Spacer()
            VStack(spacing: 10) {
                Button { Task { await respond(true) } } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text("Accepteer")
                    }
                    .frame(maxWidth: 280).padding(.vertical, 6)
                }
                .pasrGlassButton(prominent: true)
                .tint(Brand.iris)
                Button("Weiger", role: .destructive) { Task { await respond(false) } }
                    .padding(.top, 4)
                Button("Later") { dismiss() }
                    .foregroundStyle(.secondary)
            }
            .disabled(busy)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Brand.ink.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { appeared = true } }
    }

    private func respond(_ accept: Bool) async {
        busy = true
        defer { busy = false }
        do {
            try await GroupService.shared.respond(invite, accept: accept, in: context)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct InviteRow: View {
    let invite: GroupService.Invite
    let respond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                GroupBadge()
                VStack(alignment: .leading, spacing: 2) {
                    Text(invite.groupName).font(.headline)
                    Text("Van \(invite.from)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Accepteer") { respond(true) }.buttonStyle(.borderedProminent).tint(Brand.iris)
                Button("Weiger", role: .destructive) { respond(false) }.buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Rond icoon met twee personen, in de kleuren van Pasr.
struct GroupBadge: View {
    var body: some View {
        Image(systemName: "person.2.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct Avatar: View {
    let text: String
    var body: some View {
        Text(String(text.prefix(1)).uppercased())
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .frame(width: 34, height: 34)
            .background(Brand.iris.opacity(0.35), in: Circle())
    }
}

/// Twee kaartstapels die naar elkaar toe schuiven en één gedeelde kaart in het midden: het beeld van delen.
struct SharedStackArt: View {
    @State private var together = false

    var body: some View {
        ZStack {
            card(Brand.coral).rotationEffect(.degrees(together ? -14 : -24)).offset(x: together ? -44 : -70, y: 6)
            card(Brand.mint).rotationEffect(.degrees(together ? 14 : 24)).offset(x: together ? 44 : 70, y: 6)
            card(Brand.iris)
                .overlay(Image(systemName: "person.2.fill").font(.title3.weight(.semibold)).foregroundStyle(.white))
                .offset(y: together ? -6 : 8)
                .scaleEffect(together ? 1.05 : 0.95)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.6).delay(0.15)) { together = true }
        }
        .accessibilityHidden(true)
    }

    private func card(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color.gradient)
            .frame(width: 96, height: 96 / Brand.cardAspect)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}
