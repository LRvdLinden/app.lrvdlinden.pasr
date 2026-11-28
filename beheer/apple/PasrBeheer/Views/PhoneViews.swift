import SwiftUI

/// iPhone, tab Mensen: Gebruikers en Ondernemers met een schakelaar bovenaan.
struct PeopleView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mensen", selection: Binding<AppSection>(
                get: { session.section == .businesses ? .businesses : .accounts },
                set: { session.section = $0 }
            )) {
                Text("Gebruikers").tag(AppSection.accounts)
                Text("Ondernemers").tag(AppSection.businesses)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            Group {
                if session.section == .businesses { BusinessesView() } else { AccountsView() }
            }
            .id(session.section == .businesses)
        }
        .background(Theme.bg)
    }
}

/// iPhone, tab Berichten: de twee postvakken (Support en Ondernemers) met een schakelaar bovenaan.
struct MessagesView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        VStack(spacing: 0) {
            Picker("Postvak", selection: Binding<AppSection>(
                get: { session.section == .ownersMail ? .ownersMail : .supportMail },
                set: { session.section = $0 }
            )) {
                Text(verbatim: unreadTitle("Support", session.mailUnread)).tag(AppSection.supportMail)
                Text(verbatim: unreadTitle("Ondernemers", session.mailUnreadOwners)).tag(AppSection.ownersMail)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 8)
            MailView(box: session.section == .ownersMail ? .zakelijk : .pasr)
        }
        .background(Theme.bg)
    }

    private func unreadTitle(_ name: String, _ n: Int) -> String { n > 0 ? "\(name) (\(n))" : name }
}

/// iPhone, tab Meer: wat niet in de vier andere tabs past.
struct MoreView: View {
    @EnvironmentObject private var session: Session
    @State private var path: [AppSection] = []

    private static let items: [AppSection] = [.stores, .news, .settings]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Inhoud") { link(.stores) }
                Section("Support") { link(.news) }
                Section { link(.settings) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Meer")
            .navigationDestination(for: AppSection.self) { SectionContent(section: $0) }
        }
        .task(id: session.section) {
            if Self.items.contains(session.section), path.last != session.section { path = [session.section] }
        }
    }

    private func link(_ s: AppSection) -> some View {
        NavigationLink(value: s) { Label(LocalizedStringKey(s.title), systemImage: s.icon) }
            .listRowBackground(Theme.card)
    }
}
