import SwiftUI

/// Inloggen → zaak registreren → wachten op goedkeuring → de app (tabbladen volgens je rol).
struct RootView: View {
    @Environment(BusinessStore.self) private var store
    @Environment(Account.self) private var account

    var body: some View {
        Group {
            if !account.isSignedIn {
                WelcomeView()
            } else if !store.loaded {
                loadingView
            } else if let business = store.current {
                if business.isApproved {
                    MainTabs(business: business)
                        .id(business.id)
                } else {
                    PendingView(business: business)
                }
            } else {
                RegisterBusinessView()
            }
        }
        .task(id: account.session?.userID) {
            if account.isSignedIn { await store.load() } else { store.reset() }
        }
        .sheet(isPresented: Binding(get: { store.pendingInvite != nil && account.isSignedIn && !ModalTracker.shared.locked },
                                    set: { if !$0 { store.pendingInvite = nil } })) {
            if let code = store.pendingInvite {
                InviteAcceptView(code: code).trackModal()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ZakelijkLogo(size: 26)
            if let error = store.error {
                ContentUnavailableView {
                    Label("Laden lukt niet", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Opnieuw proberen") { Task { await store.load() } }
                        .buttonStyle(.borderedProminent)
                    Button("Uitloggen", role: .destructive) { Task { await account.signOut() } }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// Tabbladen: eigenaar ziet alles, een medewerker alleen Scannen (en Instellingen voor uitloggen).
struct MainTabs: View {
    let business: Business
    @AppStorage("ui.tab") private var tab = "scan"

    var body: some View {
        TabView(selection: $tab) {
            ScanView(business: business)
                .tabItem { Label("Scannen", systemImage: "qrcode.viewfinder") }
                .tag("scan")
            if business.isOwner {
                CardsView(business: business)
                    .tabItem { Label("Kaarten", systemImage: "rectangle.stack") }
                    .tag("cards")
                OverviewView(business: business)
                    .tabItem { Label("Overzicht", systemImage: "chart.xyaxis.line") }
                    .tag("overview")
                StaffView(business: business)
                    .tabItem { Label("Medewerkers", systemImage: "person.2") }
                    .tag("staff")
            }
            SettingsView(business: business)
                .tabItem { Label("Instellingen", systemImage: "gearshape") }
                .tag("settings")
        }
        .onAppear {
            if !business.isOwner && !["scan", "settings"].contains(tab) { tab = "scan" }
        }
    }
}

/// Zaakkiezer bovenin (alleen bij meer dan één zaak).
struct BusinessPicker: ToolbarContent {
    @Environment(BusinessStore.self) private var store

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if store.businesses.count > 1, let current = store.current {
                Menu {
                    ForEach(store.businesses) { b in
                        Button {
                            store.select(b.id)
                        } label: {
                            if b.id == current.id {
                                Label(b.name, systemImage: "checkmark")
                            } else {
                                Text(verbatim: b.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: current.name).font(.headline).lineLimit(1)
                        Image(systemName: "chevron.down.circle.fill").font(.footnote).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityLabel(Text("Kies een zaak"))
            }
        }
    }
}
