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
                    #if os(macOS)
                    MacMainView(business: business)
                        .id(business.id)
                    #else
                    MainTabs(business: business)
                        .id(business.id)
                    #endif
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
    @State private var router = CommunityRouter.shared
    @State private var modals = ModalTracker.shared
    @State private var accepting = false
    @State private var navigator = AppNavigator.shared

    var body: some View {
        TabView(selection: $tab) {
            ScanView(business: business)
                .tabItem { Label("Scannen", systemImage: "qrcode.viewfinder") }
                .tag("scan")
            if business.isOwner {
                CardsView(business: business)
                    .tabItem { Label("Acties", systemImage: "tag") }
                    .tag("cards")
                    .badge(router.inviteCount)
                BusinessPromotionHub(business: business)
                    .tabItem { Label("Promotie", systemImage: "photo.on.rectangle") }
                    .tag("promotion")
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
        // link uit een widget of melding: naar het juiste tabblad
        .onChange(of: navigator.request, initial: true) { _, target in
            guard let target else { return }
            navigator.request = nil
            tab = Self.tab(for: target.section, owner: business.isOwner)
        }
        // gezamenlijke acties: melding of geaccepteerde link opent Samenwerkingen onder Acties (alleen eigenaar)
        .onChange(of: router.focus, initial: true) { _, focus in
            guard focus != nil else { return }
            if business.isOwner { tab = "cards" } else { router.focus = nil }
        }
        .task(id: business.id) { await router.refreshCount(business: business) }
        .busyWhile(router.pendingToken != nil)
        .alert("Uitnodiging voor een gezamenlijke actie",
               isPresented: Binding(get: { router.pendingToken != nil && !modals.locked && !accepting },
                                    set: { if !$0 && !accepting { router.pendingToken = nil } })) {
            if business.isOwner {
                Button("Meedoen") {
                    let token = router.pendingToken
                    accepting = true
                    Task { await acceptToken(token) }
                }
                Button("Niet nu", role: .cancel) { router.pendingToken = nil }
            } else {
                Button("OK", role: .cancel) { router.pendingToken = nil }
            }
        } message: {
            if business.isOwner {
                Text("Doet \(business.name) mee aan deze gezamenlijke actie? Klantgegevens worden niet tussen ondernemingen gedeeld.")
            } else {
                Text("Alleen de eigenaar van de zaak kan een uitnodiging voor een gezamenlijke actie accepteren.")
            }
        }
    }

    /// Tabblad bij een onderdeel van het dashboard (widgets gebruiken dezelfde ids als de Mac-app en pasr.nl).
    static func tab(for section: ZakelijkSection, owner: Bool) -> String {
        guard owner else { return section == .instellingen ? "settings" : "scan" }
        switch section {
        case .scannen: return "scan"
        case .vandaag, .inzichten: return "overview"
        case .promotiemateriaal: return "promotion"
        case .medewerkers: return "staff"
        case .instellingen: return "settings"
        case .stempelkaarten, .klantenkaarten, .tickets, .kortingsbonnen, .actiecodes, .gezamenlijkeActies, .beloningen,
             .marketing, .vestigingen:
            return "cards"
        }
    }

    /// Uitnodigingslink (https://pasr.nl/zakelijk/uitnodiging/?t=TOKEN) accepteren voor de gekozen zaak.
    @MainActor private func acceptToken(_ token: String?) async {
        defer { accepting = false; router.pendingToken = nil }
        guard let token else { return }
        do {
            let r = try await Account.shared.rpc("pasr_business_community_accept_token",
                                                 ["p_business": business.id, "p_token": token])
            router.focus = CommunityRouter.Focus(kind: "community_active", campaign: JSONObject(r)?.string("campaign_id"),
                                                 notice: String(localized: "Je onderneming doet nu mee aan de gezamenlijke actie."))
        } catch {
            router.focus = CommunityRouter.Focus(kind: "community_error", campaign: nil,
                                                 notice: error.localizedDescription, failed: true)
        }
    }
}

/// Zaakkiezer bovenin (alleen bij meer dan één zaak).
struct BusinessPicker: ToolbarContent {
    @Environment(BusinessStore.self) private var store

    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif

    var body: some ToolbarContent {
        ToolbarItem(placement: .barLeading) {
            // op de Mac staat de zaakkiezer in de werkbalk van het venster (MacToolbar)
            if !Self.isMac, store.businesses.count > 1, let current = store.current {
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
