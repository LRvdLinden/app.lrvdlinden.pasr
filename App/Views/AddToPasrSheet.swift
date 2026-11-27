import SwiftUI
import SwiftData

/// "Voeg toe aan Pasr": de knop op sites van ondernemers, pasr.nl en QR-codes linkt naar
/// https://pasr.nl/add/<soort>/<id> (of pasr://add/<soort>/<id> vanaf de terugvalpagina).
/// k = stempelkaart van een zaak, c = kortingsbon, a = actiecode (alle drie een uuid uit de database),
/// t = ticket, g = cadeaukaart, s = winkelkaart (id uit de catalogus, bijv. "ah").
/// Sinds 1.0.5 (build 66): e = aanmelden voor een gratis event van een zaak (event-uuid), m = klantenkaart met barcode
/// van een zaak (kaart-uuid) en t/<ticket-uuid>?c=<code> = een ticket (aangemeld zonder account) aan je account koppelen.
struct AddLink: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case business = "k", coupon = "c", promo = "a", ticket = "t", gift = "g", store = "s", event = "e", member = "m"
    }

    let kind: Kind
    let itemID: String
    /// Code van een ticket (/add/t/<ticket>?c=<code>).
    var code: String? = nil
    var id: String { kind.rawValue + "/" + itemID + (code.map { "?" + $0 } ?? "") }

    /// Ticket van een zaak koppelen (pasr_event_ticket_claim) in plaats van een ticket uit de catalogus.
    var isTicketClaim: Bool { kind == .ticket && code != nil && UUID(uuidString: itemID) != nil }

    var webURL: URL { URL(string: "https://pasr.nl/add/\(kind.rawValue)/\(itemID)")! }

    /// https://pasr.nl/add/k/<uuid> (ook www. en met een / aan het eind) en pasr://add/k/<uuid>.
    static func parse(_ url: URL) -> AddLink? {
        let host = url.host()?.lowercased() ?? ""
        var parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "https" && (host == "pasr.nl" || host == "www.pasr.nl") {
            guard parts.first == "add" else { return nil }
            parts.removeFirst()
        } else if url.scheme == "pasr" && host == "add" {
            // pasr://add/k/<id>
        } else {
            return nil
        }
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]) else { return nil }
        let raw = parts[1].removingPercentEncoding ?? parts[1]
        guard raw.range(of: "^[A-Za-z0-9][A-Za-z0-9-]{0,63}$", options: .regularExpression) != nil else { return nil }
        switch kind {
        case .business, .coupon, .promo, .event, .member:
            guard UUID(uuidString: raw) != nil else { return nil }
            return AddLink(kind: kind, itemID: raw.lowercased())
        case .ticket where UUID(uuidString: raw) != nil:
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "c" || $0.name == "code" }?.value?.trimmingCharacters(in: .whitespaces)
            if let code, code.range(of: "^[A-Za-z0-9-]{8,80}$", options: .regularExpression) != nil {
                return AddLink(kind: .ticket, itemID: raw.lowercased(), code: code)
            }
            return AddLink(kind: kind, itemID: raw)
        default:
            return AddLink(kind: kind, itemID: raw)
        }
    }

    var kindTitle: String {
        switch kind {
        case .business: String(localized: "Stempelkaart")
        case .coupon: String(localized: "Kortingsbon")
        case .promo: String(localized: "Actiecode")
        case .ticket: String(localized: "Ticket")
        case .gift: String(localized: "Cadeaukaart")
        case .store: String(localized: "Klantenkaart")
        case .event: String(localized: "Aanmelden")
        case .member: String(localized: "Klantenkaart")
        }
    }
}

/// Kiest het juiste venster bij een /add/-link: aanmelden voor een event, klantenkaart van een zaak, ticket koppelen,
/// of het algemene "Toevoegen aan Pasr?".
struct AddLinkSheet: View {
    let link: AddLink

    var body: some View {
        if link.kind == .event {
            EventSignupSheet(eventID: link.itemID)
        } else if link.kind == .member {
            MemberCardJoinSheet(cardID: link.itemID)
        } else if link.isTicketClaim, let code = link.code {
            TicketClaimSheet(ticketID: link.itemID, code: code)
        } else {
            AddToPasrSheet(link: link)
        }
    }
}

/// Het venster "Toevoegen aan Pasr?": voorbeeld van het item in de stijl van de zaak, één knop, en daarna "Toegevoegd"
/// met "Bekijk in Pasr". Gebruikt de bestaande stromen: pasr_business_join, pasr_business_coupon_claim,
/// pasr_business_promo_claim en Kaart toevoegen bij een winkel uit de catalogus.
struct AddToPasrSheet: View {
    let link: AddLink
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]

    enum Phase: Equatable { case loading, ready, missing(String), added }

    @State private var phase: Phase = .loading
    @State private var busy = false
    @State private var error: String?
    // stempelkaart
    @State private var business: BusinessCards.Info?
    @State private var addedCardID: UUID?
    // kortingsbon of actiecode
    @State private var offer: PasrCouponsView.Coupon?
    @State private var offerSaved = false
    // winkel, cadeaukaart of ticket uit de catalogus
    @State private var template: StoreTemplate?
    @State private var showAddCard = false
    @State private var countBefore = 0

    private var signedIn: Bool { AccountService.shared.isSignedIn }

    private var existingBusinessCard: Card? {
        guard link.kind == .business else { return nil }
        return cards.first { $0.details.businessCardId == link.itemID }
    }

    private var existingStoreCards: [Card] {
        guard let template else { return [] }
        return cards.filter { $0.templateID?.lowercased() == template.id.lowercased() && !$0.isTemporary }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    switch phase {
                    case .loading:
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.quaternary)
                            .aspectRatio(Brand.cardAspect, contentMode: .fit)
                            .frame(maxWidth: 380)
                            .overlay { ProgressView() }
                    case .missing(let message):
                        ContentUnavailableView {
                            Label(message, systemImage: "exclamationmark.triangle")
                        } description: {
                            Text("Vraag de zaak om een nieuwe link, of zoek het item in Kaart toevoegen.")
                        }
                        Button("Sluiten") { dismiss() }
                            .pasrGlassButton(prominent: true)
                            .tint(Brand.iris)
                    case .ready:
                        readyView
                    case .added:
                        addedView
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle(phase == .added ? Text("Toegevoegd") : Text("Toevoegen aan Pasr?"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .added ? "Klaar" : "Annuleer", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showAddCard, onDismiss: checkStoreAdded) {
                if let template { AddCardView(store: template) }
            }
        }
    }

    // MARK: Weergave

    @ViewBuilder private var readyView: some View {
        Text(link.kindTitle.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
        preview
            .frame(maxWidth: 380)
        Text(summary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        if let error {
            Text(error).font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center)
        }
        if let already = alreadyText {
            Label(already, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.mint)
            Button { openInPasr() } label: {
                Label("Bekijk in Pasr", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    .frame(maxWidth: 260).padding(.vertical, 6)
            }
            .pasrGlassButton(prominent: true)
            .tint(Brand.iris)
            if [AddLink.Kind.store, .gift, .ticket].contains(link.kind) {
                Button("Nog een toevoegen") { startStoreAdd() }
            }
        } else {
            Button { Task { await add() } } label: {
                HStack {
                    if busy { ProgressView() }
                    Label("Toevoegen aan Pasr", systemImage: "plus")
                }
                .frame(maxWidth: 260).padding(.vertical, 6)
            }
            .pasrGlassButton(prominent: true)
            .tint(Brand.iris)
            .disabled(busy || needsAccount)
            if needsAccount {
                Text("Log eerst in met je Pasr-account (Instellingen › Account); een kortingsbon of actiecode krijgt een persoonlijke code die bij je account hoort.")
                    .font(.footnote)
                    .foregroundStyle(Brand.coral)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder private var preview: some View {
        switch link.kind {
        case .business:
            CardFaceView(appearance: existingBusinessCard.map { CardAppearance($0) } ?? businessAppearance, showsCode: false)
                .aspectRatio(Brand.cardAspect, contentMode: .fit)
        case .coupon, .promo:
            if let offer {
                PasrDiscountCard(business: offer.business, title: offer.title, discount: offer.discount,
                                 kind: offer.isPromo ? "Actiecode" : "Kortingscoupon", logo: offer.logo, color: offer.color,
                                 state: offerSaved ? .saved : .available, expires: offer.end)
            }
        case .ticket, .gift, .store:
            CardFaceView(appearance: storeAppearance, showsCode: false)
                .aspectRatio(Brand.cardAspect, contentMode: .fit)
        case .event, .member:
            EmptyView()   // eigen vensters (AddLinkSheet)
        }
    }

    @ViewBuilder private var addedView: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 64))
            .foregroundStyle(Brand.mint)
            .symbolEffect(.bounce, value: phase == .added)
        Text("Toegevoegd").font(.title.bold())
        preview.frame(maxWidth: 320)
        Text(link.kind == .coupon || link.kind == .promo
             ? "Je persoonlijke code staat bij Kortingsbonnen. Laat hem aan de kassa scannen."
             : "Het staat in je Pasr.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        Button { openInPasr() } label: {
            Label("Bekijk in Pasr", systemImage: "rectangle.portrait.on.rectangle.portrait")
                .frame(maxWidth: 260).padding(.vertical, 6)
        }
        .pasrGlassButton(prominent: true)
        .tint(Brand.iris)
    }

    private var businessAppearance: CardAppearance {
        var a = CardAppearance(storeName: business?.displayName ?? String(localized: "Stempelkaart"), number: "", format: .qr,
                               colorHex: business?.color ?? "#6A5CFF", kind: .stamps)
        var d = CardDetails()
        d.stampsTotal = business?.stampsTotal ?? CardDetails.defaultStamps
        d.stampsCount = 0
        d.reward = business?.reward
        a.details = d
        return a
    }

    private var storeAppearance: CardAppearance {
        guard let t = template else {
            return CardAppearance(storeName: "", number: "", format: .qr, colorHex: "#2B2F3A", kind: .loyalty)
        }
        let domain = t.domain.isEmpty ? nil : t.domain
        var a = CardAppearance(storeName: t.name, number: "", format: t.format, colorHex: t.cardHex, kind: t.kind,
                               logoData: domain.flatMap { LogoService.bundledLogo(for: $0) ?? LogoService.cachedLogo(for: $0) },
                               logoStyle: StoreLogoStyles.style(for: domain))
        a.storeCover = t.kind == .voucher ? RemoteStores.cover(for: t.id) : nil
        if t.kind == .ticket {
            a.ticket = TicketInfo.resolve(name: t.name, templateID: t.id, details: CardDetails(), website: domain)
        }
        return a
    }

    private var summary: String {
        switch link.kind {
        case .business:
            let reward = business?.reward.map { String(localized: " voor \($0)") } ?? ""
            return String(localized: "Spaar \(business?.stampsTotal ?? CardDetails.defaultStamps) stempels\(reward). De zaak ziet alleen je klantcode en de stand, niet wie je bent.")
        case .coupon, .promo:
            guard let offer else { return "" }
            return offer.business + " · " + offer.title
        case .ticket:
            return String(localized: "Pasr zet het ticket klaar in de stijl van het evenement. Daarna scan je de code van je eigen ticket.")
        case .gift:
            return String(localized: "Pasr zet de cadeaukaart klaar met logo en kleur. Daarna scan of typ je het nummer van je eigen kaart.")
        case .store:
            return String(localized: "Pasr zet de kaart klaar met logo en kleur. Daarna scan of typ je het nummer van je eigen kaart.")
        case .event, .member:
            return ""
        }
    }

    private var alreadyText: String? {
        switch link.kind {
        case .business: existingBusinessCard == nil ? nil : String(localized: "Deze stempelkaart staat al in je Pasr.")
        case .coupon, .promo: offerSaved ? String(localized: "Deze aanbieding staat al in je Pasr.") : nil
        default: existingStoreCards.isEmpty ? nil : String(localized: "Deze kaart staat al in je Pasr.")
        }
    }

    private var needsAccount: Bool { (link.kind == .coupon || link.kind == .promo) && !signedIn && !offerSaved }

    // MARK: Ophalen en toevoegen

    private func load() async {
        switch link.kind {
        case .business:
            if existingBusinessCard != nil { phase = .ready }
            business = await BusinessCards.preview(cardID: link.itemID)
            if existingBusinessCard == nil {
                phase = business?.active == true ? .ready : .missing(String(localized: "Deze stempelkaart is niet (meer) online."))
            }
        case .coupon, .promo:
            await loadOffer()
        case .ticket, .gift, .store:
            if StoreTemplates.template(id: link.itemID) == nil { await StoreCatalog.shared.refresh(force: true) }
            template = StoreTemplates.template(id: link.itemID)
            phase = template == nil ? .missing(String(localized: "Deze kaart staat niet (meer) in Pasr.")) : .ready
        case .event, .member:
            phase = .ready
        }
    }

    private func loadOffer() async {
        let isPromo = link.kind == .promo
        do {
            let rows = try await AccountService.shared.publicRPC(isPromo ? "pasr_business_promo_public" : "pasr_business_coupon_list", body: [:])
            let match = (rows as? [[String: Any]] ?? []).first { ($0["id"] as? String)?.lowercased() == link.itemID }
            if signedIn {
                let mine = try? await AccountService.shared.rpc(isPromo ? "pasr_business_promo_mine" : "pasr_business_coupon_mine", body: [:])
                offerSaved = (mine as? [[String: Any]] ?? []).contains {
                    (($0[isPromo ? "promo_id" : "coupon_id"]) as? String)?.lowercased() == link.itemID
                }
            }
            guard var row = match else {
                phase = .missing(isPromo ? String(localized: "Deze actiecode is verlopen of niet gevonden.")
                                         : String(localized: "Deze kortingsbon is verlopen of niet gevonden."))
                return
            }
            if isPromo { row["kind"] = "code" }
            offer = PasrCouponsView.Coupon(row)
            if let end = offer?.end, end < .now {
                phase = .missing(String(localized: "Deze aanbieding is verlopen."))
                return
            }
            phase = offer == nil ? .missing(String(localized: "Deze aanbieding is niet gevonden.")) : .ready
        } catch {
            phase = .missing(String(localized: "Pasr kan de aanbieding nu niet ophalen. Probeer het zo opnieuw."))
        }
    }

    private func add() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            switch link.kind {
            case .business:
                let card = try await BusinessCards.join(cardID: link.itemID, preview: business, in: context)
                addedCardID = card.id
                withAnimation { phase = .added }
            case .coupon, .promo:
                let isPromo = link.kind == .promo
                _ = try await AccountService.shared.rpc(isPromo ? "pasr_business_promo_claim" : "pasr_business_coupon_claim",
                                                        body: [isPromo ? "p_promo" : "p_coupon": link.itemID])
                offerSaved = true
                withAnimation { phase = .added }
            case .ticket, .gift, .store:
                startStoreAdd()
            case .event, .member:
                break
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startStoreAdd() {
        countBefore = existingStoreCards.count
        showAddCard = true
    }

    /// Kaart toevoegen is dicht: staat er nu een kaart van deze winkel meer in Pasr, dan is hij toegevoegd.
    private func checkStoreAdded() {
        let now = existingStoreCards
        if now.count > countBefore {
            addedCardID = now.max { $0.createdAt < $1.createdAt }?.id
            withAnimation { phase = .added }
        }
    }

    private func openInPasr() {
        switch link.kind {
        case .coupon, .promo:
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                NotificationCenter.default.post(name: .pasrOpenCoupons, object: nil)
            }
        default:
            let id = addedCardID ?? existingBusinessCard?.id ?? existingStoreCards.first?.id
            dismiss()
            if let id { NotificationRouter.pendingCardID = id }
        }
    }
}
