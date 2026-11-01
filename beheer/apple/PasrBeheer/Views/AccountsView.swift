import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var session: Session
    @State private var users: [User] = []
    @State private var total = 0
    @State private var search = ""
    @State private var filter = "all"
    @State private var loading = false
    @State private var error: String?
    @State private var deleting: User?
    @State private var toast: String?

    private static let filters = [("all", "Alle"), ("unconfirmed", "Onbevestigd"), ("cards", "Met kaarten"), ("active", "Actief")]

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Self.filters, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if let error {
                Text(error).foregroundStyle(Theme.coral).font(.subheadline)
            }
            Section {
                ForEach(users) { u in
                    NavigationLink(value: u) { UserRow(user: u) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleting = u } label: { Label("Verwijder", systemImage: "trash") }
                            if !u.isConfirmed {
                                Button { Task { await resend(u) } } label: { Label("Mail opnieuw", systemImage: "envelope.arrow.triangle.branch") }
                                    .tint(Theme.iris)
                            }
                        }
                        .contextMenu {
                            if !u.isConfirmed {
                                Button { Task { await resend(u) } } label: { Label("Bevestigingsmail opnieuw", systemImage: "envelope") }
                            }
                            Button(role: .destructive) { deleting = u } label: { Label("Verwijder account", systemImage: "trash") }
                        }
                }
                if users.count < total {
                    HStack {
                        Spacer()
                        if loading { ProgressView() } else { Button("Meer laden") { Task { await load(reset: false) } } }
                        Spacer()
                    }
                }
            } header: {
                Text(Fmt.plural(total, "account", "accounts"))
            }
            if !loading && users.isEmpty && error == nil {
                ContentUnavailableView(search.isEmpty ? "Nog geen accounts" : "Geen accounts gevonden",
                                       systemImage: "person.crop.circle.badge.questionmark")
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Accounts")
        .navigationDestination(for: User.self) { u in
            UserDetailView(user: u, onResend: { await resend(u) }, onDelete: { deleting = u })
        }
        .searchable(text: $search, prompt: "Zoek op e-mail of naam")
        .refreshable { await load(reset: true) }
        .task(id: "\(filter)|\(search)|\(session.refreshTick)") {
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
        .confirmationDialog("Account verwijderen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { u in
            Button("Verwijder \(u.email ?? "account")", role: .destructive) { Task { await delete(u) } }
        } message: { u in
            Text("Het account en de \(Fmt.plural(u.cards, "kaart", "kaarten")) erin worden van de server verwijderd. De kaarten op de apparaten van deze persoon blijven staan. Dit kan niet ongedaan worden.")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.card2, in: Capsule())
                    .overlay(Capsule().stroke(Theme.line))
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func load(reset: Bool) async {
        loading = true
        defer { loading = false }
        do {
            let r = try await session.call("users", ["search": search, "filter": filter, "limit": 50, "offset": reset ? 0 : users.count],
                                           as: UsersResponse.self)
            total = r.total
            users = reset ? r.users : users + r.users
            error = nil
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resend(_ u: User) async {
        do {
            try await session.call("user_resend", ["id": u.id])
            show("Bevestigingsmail verstuurd")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func delete(_ u: User) async {
        do {
            try await session.call("user_delete", ["id": u.id])
            withAnimation { users.removeAll { $0.id == u.id } }
            total = max(0, total - 1)
            show("Account verwijderd")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if toast == text { toast = nil } }
        }
    }
}

struct UserRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            Avatar(user: user, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.email ?? "—").font(.body.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 8) {
                    StatusBadge(confirmed: user.isConfirmed)
                    if let c = user.country { Text(Fmt.flag(c)) }
                    Text(Fmt.plural(user.cards, "kaart", "kaarten"))
                    Text("· \(Fmt.ago(user.created_at))")
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 2)
    }
}

struct Avatar: View {
    let user: User
    var size: CGFloat = 40

    var body: some View {
        Text(user.initial)
            .font(.system(size: size * 0.42, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Theme.iris, Theme.coral], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let confirmed: Bool

    var body: some View {
        Text(confirmed ? "Bevestigd" : "Onbevestigd")
            .font(.caption2.weight(.bold))
            .foregroundStyle(confirmed ? Theme.mint : Theme.amber)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background((confirmed ? Theme.mint : Theme.amber).opacity(0.13), in: Capsule())
    }
}

struct UserDetailView: View {
    let user: User
    var onResend: () async -> Void
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Avatar(user: user, size: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.first_name ?? "Geen voornaam").font(.headline)
                        Text(user.email ?? "—").font(.subheadline).foregroundStyle(Theme.muted).textSelection(.enabled)
                        StatusBadge(confirmed: user.isConfirmed)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Gegevens") {
                LabeledContent("Kaarten op de server", value: Fmt.n(user.cards))
                LabeledContent("Land", value: user.country.map { "\(Fmt.flag($0)) \(Fmt.country($0))" } ?? "onbekend")
                LabeledContent("Aangemaakt", value: Fmt.ago(user.created_at))
                LabeledContent("Bevestigd", value: user.isConfirmed ? Fmt.ago(user.email_confirmed_at) : "nog niet")
                LabeledContent("Laatst ingelogd", value: Fmt.ago(user.last_sign_in_at))
                LabeledContent("Laatste sync", value: Fmt.ago(user.synced_at))
            }
            Section {
                if !user.isConfirmed {
                    Button { Task { await onResend() } } label: { Label("Bevestigingsmail opnieuw sturen", systemImage: "envelope") }
                }
                Button(role: .destructive) {
                    dismiss()
                    onDelete()
                } label: { Label("Account verwijderen", systemImage: "trash") }
            } footer: {
                Text("De inhoud van kaarten staat versleuteld op de server en is in het beheer niet te zien.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(user.email ?? "Account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
