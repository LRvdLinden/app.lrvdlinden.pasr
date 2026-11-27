import SwiftUI

/// Hoofdvenster van Pasr Zakelijk op de Mac: zijbalk in dezelfde groepen als het dashboard op pasr.nl
/// (Vandaag · Klantenbinding · Groei · Je zaak), werkbalk met zaakkiezer, zoeken en Scannen.
/// Een medewerker ziet alleen Scannen en Instellingen.
struct MacMainView: View {
    let business: Business
    @AppStorage("mac.section") private var stored = ZakelijkSection.vandaag.rawValue
    @State private var selection: ZakelijkSection? = .vandaag
    @State private var navigator = AppNavigator.shared
    @State private var router = CommunityRouter.shared
    @State private var commands = MacCommandCenter.shared
    @State private var search = ""
    @State private var searching = false
    @State private var creating: MacNewItem?

    var body: some View {
        NavigationSplitView {
            MacSidebar(business: business, selection: $selection, inviteCount: router.inviteCount)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
                .environment(\.isEmbeddedPane, true)
                .pasrFormStyle()
                // het paneel past zich aan het venster aan en duwt nooit de zijbalk of de vensterknoppen weg
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .id(selection)
        }
        .searchable(text: $search, isPresented: $searching, placement: .toolbar, prompt: Text("Zoek in je zaak"))
        .searchSuggestions { MacSearchResults(business: business, query: search) { pick($0) } }
        .toolbar { MacToolbar(business: business) }
        .navigationTitle(Text(verbatim: business.name))
        .onAppear {
            let s = ZakelijkSection(rawValue: stored) ?? .vandaag
            selection = allowed(s) ? s : (business.isOwner ? .vandaag : .scannen)
        }
        .onChange(of: selection) { _, s in if let s { stored = s.rawValue } }
        // link uit een widget, melding of het menu
        .onChange(of: navigator.request, initial: true) { _, target in
            guard let target else { return }
            navigator.request = nil
            go(target.section)
        }
        // gezamenlijke acties: melding of geaccepteerde link opent Gezamenlijke acties (alleen eigenaar)
        .onChange(of: router.focus, initial: true) { _, focus in
            guard focus != nil else { return }
            if business.isOwner { selection = .gezamenlijkeActies } else { router.focus = nil }
        }
        .onChange(of: commands.searchTick) { _, _ in searching = true }
        .onChange(of: commands.newItem) { _, item in
            guard let item else { return }
            commands.newItem = nil
            create(item)
        }
        .task(id: business.id) { await router.refreshCount(business: business) }
        .modifier(MacCreateSheets(business: business, creating: $creating))
        .modifier(MacCommunityAlert(business: business))
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .vandaag {
        case .vandaag: MacTodayPane(business: business) { go($0) }
        case .scannen: ScanView(business: business)
        case .stempelkaarten: CardsView(business: business)
        case .klantenkaarten: MacMemberCardsPane(business: business)
        case .tickets: MacTicketsPane(business: business)
        case .kortingsbonnen: BusinessCouponsView(business: business)
        case .actiecodes: BusinessPromoCodesView(business: business)
        case .gezamenlijkeActies: BusinessCommunityView(business: business)
        case .beloningen: MacRewardsPane(business: business)
        case .inzichten: OverviewView(business: business)
        case .marketing: BusinessMarketingView(business: business)
        case .promotiemateriaal: BusinessPromotionHub(business: business)
        case .vestigingen: BusinessLocationsView(business: business)
        case .medewerkers: StaffView(business: business)
        case .instellingen: SettingsView(business: business)
        }
    }

    private func allowed(_ section: ZakelijkSection) -> Bool {
        business.isOwner || section == .scannen || section == .instellingen
    }

    private func go(_ section: ZakelijkSection) {
        selection = allowed(section) ? section : .scannen
    }

    private func pick(_ result: MacSearchResults.Pick) {
        search = ""
        searching = false
        go(result.section)
    }

    private func create(_ item: MacNewItem) {
        guard business.isOwner else { return }
        switch item {
        case .stampCard:
            selection = .stempelkaarten
            if business.cards.count < 5 { creating = item }
        case .coupon: selection = .kortingsbonnen
        case .promoCode: selection = .actiecodes
        case .event:
            selection = .tickets
            creating = item
        case .memberCard:
            selection = .klantenkaarten
            creating = item
        case .community: selection = .gezamenlijkeActies
        }
    }
}

/// Zijbalk: Vandaag (en Scannen) bovenaan, daarna de groepen van het dashboard.
private struct MacSidebar: View {
    let business: Business
    @Binding var selection: ZakelijkSection?
    let inviteCount: Int

    var body: some View {
        List(selection: $selection) {
            if business.isOwner {
                Section {
                    row(.vandaag)
                    row(.scannen)
                }
                Section("Klantenbinding") {
                    row(.stempelkaarten)
                    row(.klantenkaarten)
                    row(.tickets)
                    row(.kortingsbonnen)
                    row(.actiecodes)
                    row(.gezamenlijkeActies, badge: inviteCount)
                    row(.beloningen)
                }
                Section("Groei") {
                    row(.inzichten)
                    row(.marketing)
                    row(.promotiemateriaal)
                }
                Section("Je zaak") {
                    row(.vestigingen)
                    row(.medewerkers)
                    row(.instellingen)
                }
            } else {
                Section {
                    row(.scannen)
                    row(.instellingen)
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// De tag moet als laatste: `.badge(…)` ná `.tag(…)` maakt de rij onselecteerbaar op de Mac (klikken op
    /// Gezamenlijke acties deed daardoor niets en de zijbalk liet geen selectie zien).
    private func row(_ section: ZakelijkSection, badge: Int = 0) -> some View {
        Label(section.title, systemImage: section.symbol)
            .badge(badge)
            .tag(section)
    }
}

extension ZakelijkSection {
    /// Naam in de zijbalk (Nederlandse sleutel uit Localizable.xcstrings).
    private var key: String {
        switch self {
        case .vandaag: "Vandaag"
        case .scannen: "Scannen"
        case .stempelkaarten: "Stempelkaarten"
        case .klantenkaarten: "Klantenkaarten"
        case .tickets: "Tickets"
        case .kortingsbonnen: "Kortingsbonnen"
        case .actiecodes: "Actiecodes"
        case .gezamenlijkeActies: "Gezamenlijke acties"
        case .beloningen: "Beloningen"
        case .inzichten: "Inzichten"
        case .marketing: "Marketingkalender"
        case .promotiemateriaal: "Promotiemateriaal"
        case .vestigingen: "Vestigingen"
        case .medewerkers: "Medewerkers"
        case .instellingen: "Instellingen"
        }
    }

    var title: LocalizedStringKey { LocalizedStringKey(key) }
    var localizedName: String { String(localized: String.LocalizationValue(key)) }

    var symbol: String {
        switch self {
        case .vandaag: "house"
        case .scannen: "qrcode.viewfinder"
        case .stempelkaarten: "rectangle.stack"
        case .klantenkaarten: "barcode"
        case .tickets: "ticket"
        case .kortingsbonnen: "tag"
        case .actiecodes: "number"
        case .gezamenlijkeActies: "person.3"
        case .beloningen: "gift"
        case .inzichten: "chart.bar.xaxis"
        case .marketing: "calendar"
        case .promotiemateriaal: "photo.on.rectangle"
        case .vestigingen: "mappin.and.ellipse"
        case .medewerkers: "person.2"
        case .instellingen: "gearshape"
        }
    }
}

/// Werkbalk: zaakkiezer, Scannen (eigen venster) en Nieuw.
private struct MacToolbar: ToolbarContent {
    let business: Business
    @Environment(BusinessStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if store.businesses.count > 1 {
                Picker(selection: Binding(get: { business.id }, set: { store.select($0) })) {
                    ForEach(store.businesses) { b in Text(verbatim: b.name).tag(b.id) }
                } label: {
                    Text("Kies een zaak")
                }
                .pickerStyle(.menu)
                .help(Text("Kies een zaak"))
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { openWindow(id: MacWindows.scanner) } label: {
                Label("Scannen", systemImage: "qrcode.viewfinder")
            }
            .help(Text("Scannen (⇧⌘S)"))
        }
        if business.isOwner {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    MacNewMenuItems()
                } label: {
                    Label("Nieuw", systemImage: "plus")
                }
                .help(Text("Nieuw aanmaken"))
            }
        }
    }
}

/// Wat je kunt aanmaken (werkbalk en menu Archief › Nieuw).
enum MacNewItem: String, Identifiable, CaseIterable {
    case stampCard, coupon, promoCode, event, memberCard, community
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .stampCard: "Stempelkaart"
        case .coupon: "Kortingscoupon"
        case .promoCode: "Zelfgekozen actiecode"
        case .event: "Ticket-event (gratis)"
        case .memberCard: "Klantenkaart met barcode"
        case .community: "Gezamenlijke actie"
        }
    }

    var symbol: String {
        switch self {
        case .stampCard: "rectangle.stack.badge.plus"
        case .coupon: "tag"
        case .promoCode: "number"
        case .event: "ticket"
        case .memberCard: "barcode"
        case .community: "person.3"
        }
    }
}

struct MacNewMenuItems: View {
    var body: some View {
        ForEach(MacNewItem.allCases) { item in
            Button { MacCommandCenter.shared.newItem = item } label: { Label(item.title, systemImage: item.symbol) }
        }
    }
}

/// Editors voor Nieuw (stempelkaart, event, klantenkaart) als sheet boven het hoofdvenster.
private struct MacCreateSheets: ViewModifier {
    let business: Business
    @Binding var creating: MacNewItem?

    func body(content: Content) -> some View {
        content.sheet(item: $creating) { item in
            switch item {
            case .stampCard: CardEditorView(business: business, card: BusinessCard()).trackModal()
            case .event: EventEditorView(business: business, event: TicketEvent()).trackModal()
            case .memberCard: MemberCardEditorView(business: business, card: MemberCard()).trackModal()
            default: EmptyView()
            }
        }
    }
}

/// Uitnodigingslink voor een gezamenlijke actie (zelfde vraag als op iOS).
private struct MacCommunityAlert: ViewModifier {
    let business: Business
    @State private var router = CommunityRouter.shared
    @State private var modals = ModalTracker.shared
    @State private var accepting = false

    func body(content: Content) -> some View {
        content
            .alert("Uitnodiging voor een gezamenlijke actie",
                   isPresented: Binding(get: { router.pendingToken != nil && !modals.locked && !accepting },
                                        set: { if !$0 && !accepting { router.pendingToken = nil } })) {
                if business.isOwner {
                    Button("Meedoen") {
                        let token = router.pendingToken
                        accepting = true
                        Task { await accept(token) }
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

    @MainActor private func accept(_ token: String?) async {
        defer { accepting = false; router.pendingToken = nil }
        guard let token else { return }
        do {
            let r = try await Account.shared.rpc("pasr_business_community_accept_token", ["p_business": business.id, "p_token": token])
            router.focus = CommunityRouter.Focus(kind: "community_active", campaign: JSONObject(r)?.string("campaign_id"),
                                                 notice: String(localized: "Je onderneming doet nu mee aan de gezamenlijke actie."))
        } catch {
            router.focus = CommunityRouter.Focus(kind: "community_error", campaign: nil, notice: error.localizedDescription, failed: true)
        }
    }
}
