import SwiftUI

/// Medewerkers (eigenaar): uitnodigen met een link, intrekken. Medewerkers zien alleen de scanner.
struct StaffView: View {
    let business: Business
    @State private var staff: [StaffMember] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var inviting = false
    @State private var revoking: StaffMember?
    @State private var revokedTick = 0

    private var active: [StaffMember] { staff.filter { !$0.revoked } }
    private var revoked: [StaffMember] { staff.filter { $0.revoked } }

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { Text(error).foregroundStyle(Theme.coral) }
                }
                Section {
                    ForEach(active) { member in
                        row(member, revocable: member.role != .owner)
                            .swipeActions {
                                if member.role != .owner {
                                    Button("Intrekken", role: .destructive) { revoking = member }
                                }
                            }
                            .contextMenu {
                                if member.role != .owner {
                                    Button("Intrekken", systemImage: "person.badge.minus", role: .destructive) { revoking = member }
                                }
                            }
                    }
                    if loaded && active.filter({ $0.role != .owner }).isEmpty {
                        Text("Nog geen medewerkers. Nodig iemand uit; die logt in met een eigen Pasr-account en ziet alleen de scanner.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Team")
                } footer: {
                    AppPlatform.isMac
                        ? Text("Klik op Intrekken (of klik met de rechtermuisknop op iemand) om de toegang in te trekken. Wie is ingetrokken, kan direct geen stempels meer zetten.")
                        : Text("Veeg naar links om iemand in te trekken. Wie is ingetrokken, kan direct geen stempels meer zetten.")
                }
                if !revoked.isEmpty {
                    Section("Ingetrokken") {
                        ForEach(revoked) { row($0).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Medewerkers")
            .toolbar {
                BusinessPicker()
                ToolbarItem(placement: .primaryAction) {
                    Button { inviting = true } label: { Label("Uitnodigen", systemImage: "person.badge.plus") }
                }
            }
            .refreshable { await load() }
            .macRefreshButton { await load() }
            .task { await load() }
            .overlay { if !loaded && error == nil { ProgressView() } }
            .sensoryFeedback(.success, trigger: revokedTick)
            .sheet(isPresented: $inviting, onDismiss: { Task { await load() } }) {
                InviteStaffView(business: business).trackModal()
            }
            .busyWhile(revoking != nil)
            .confirmationDialog("Medewerker intrekken?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                                titleVisibility: .visible, presenting: revoking) { member in
                Button("Intrekken", role: .destructive) { Task { await revoke(member) } }
                Button("Annuleer", role: .cancel) {}
            } message: { member in
                Text(String(format: String(localized: "%@ kan dan geen stempels meer zetten voor %@."),
                            member.name.isEmpty ? member.email : member.name, business.name))
            }
        }
    }

    private func row(_ m: StaffMember, revocable: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.role == .owner ? "crown.fill" : (m.pending ? "envelope" : "person.fill"))
                .foregroundStyle(m.role == .owner ? Theme.amber : Theme.mint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: m.name.isEmpty ? (m.email.isEmpty ? "–" : m.email) : m.name).font(.body.weight(.semibold))
                if !m.email.isEmpty && !m.name.isEmpty { Text(verbatim: m.email).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Group {
                if m.role == .owner { Text("Eigenaar") }
                else if m.revoked { Text("Ingetrokken") }
                else if m.expired { Text("Verlopen") }
                else if m.pending { Text("Uitgenodigd") }
                else { Text("Medewerker") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            // op de Mac bestaat vegen niet: een zichtbare knop in de rij
            if AppPlatform.isMac && revocable {
                Button("Intrekken", role: .destructive) { revoking = m }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: AppPlatform.isMac ? .contain : .combine)
    }

    private func load() async {
        do {
            staff = try await BusinessAPI.staff(business: business.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func revoke(_ m: StaffMember) async {
        do {
            try await BusinessAPI.revoke(staff: m.id)
            revokedTick += 1
            await load()
        } catch {
            self.error = error.localizedDescription
        }
        revoking = nil
    }
}

/// Medewerker uitnodigen: naam (en e-mail), daarna de link delen.
struct InviteStaffView: View {
    let business: Business
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var busy = false
    @State private var message: String?
    @State private var invite: StaffInvite?

    var body: some View {
        NavigationStack {
            Form {
                if let invite {
                    Section {
                        VStack(spacing: 14) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Theme.mint)
                            Text("Uitnodiging klaar").font(.title3.weight(.bold))
                            Text("Stuur deze link naar je medewerker. De link werkt 14 dagen en maar één keer.")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                            if let qr = QRCode.image(invite.link.absoluteString) {
                                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().frame(width: 180)
                                    .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 14))
                                    .accessibilityLabel(Text("QR-code van de uitnodiging"))
                            }
                            ShareLink(item: invite.link, subject: Text("Uitnodiging Pasr Zakelijk"),
                                      message: Text(String(format: String(localized: "Je bent uitgenodigd om stempels te zetten voor %@ in de app Pasr Zakelijk."), business.name))) {
                                Label("Link delen", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(BigButtonStyle())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                } else {
                    Section {
                        TextField("Naam", text: $name).textContentType(.name)
                        TextField("E-mailadres (optioneel)", text: $email)
                            .textContentType(.emailAddress)
                            .keyboard(.email)
                            .capitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Je medewerker maakt een gratis Pasr-account (of logt in) en accepteert de uitnodiging. Medewerkers kunnen alleen scannen.")
                    }
                    if let message { Section { Text(message).foregroundStyle(Theme.coral) } }
                }
            }
            .navigationTitle("Medewerker uitnodigen")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(invite == nil ? "Annuleer" : "Klaar") { dismiss() } }
                if invite == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if busy { ProgressView() } else {
                            Button("Maak link") { Task { await create() } }
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: invite?.code)
        }
    }

    private func create() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            invite = try await BusinessAPI.invite(business: business.id, name: name.trimmingCharacters(in: .whitespaces),
                                                  email: email.trimmingCharacters(in: .whitespaces))
        } catch {
            message = error.localizedDescription
        }
    }
}
