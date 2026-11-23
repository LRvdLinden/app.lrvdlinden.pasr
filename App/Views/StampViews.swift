import SwiftUI
import SwiftData

/// Onder een stempelkaart die naar voren is gehaald: alleen-lezen. De stand, de beloning en verversen; de QR-code met
/// je klantcode staat op de achterkant. Stempels zetten en inwisselen doet alleen de zaak (sinds build 43).
struct StampControls: View {
    @Bindable var card: Card
    var width: CGFloat
    @Environment(\.modelContext) private var context
    @State private var refreshing = false

    private var details: CardDetails { card.details }

    var body: some View {
        VStack(spacing: 10) {
            if details.isBusiness {
                HStack(spacing: 14) {
                    progress.frame(maxWidth: .infinity, alignment: .leading)
                    Button { Task { await refresh() } } label: {
                        if refreshing {
                            ProgressView().frame(width: 30, height: 30)
                        } else {
                            Label("Stand verversen", systemImage: "arrow.clockwise").labelStyle(.iconOnly).font(.title3).frame(width: 30, height: 30)
                        }
                    }
                    .pasrGlassButton()
                    .disabled(refreshing)
                    .accessibilityLabel(Text("Stand verversen"))
                }
            } else {
                progress
            }
        }
        .frame(width: width)
        .task(id: card.id) { if details.isBusiness { await refresh() } }
    }

    private var progress: some View {
        VStack(spacing: 2) {
            Text("\(details.stampsCountValue) van \(details.stampsTotalValue) stempels")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(details.stampsFull ? String(localized: "Vol: laat je kaart scannen om de beloning in te wisselen")
                 : String(localized: "Stempels zet de zaak · ") + details.stampsProgressText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        if await BusinessCards.refresh(card) { try? context.save() }
    }
}

/// Een join-link of QR-code van een zaak (pasr.nl/zakelijk/kaart/<id>/ of de oude …/#<id>): de kaart bekijken en toevoegen.
struct JoinBusinessSheet: View {
    let cardID: String
    /// Na toevoegen of "Toon kaart" (bijv. om Kaart toevoegen ook te sluiten).
    var onDone: (() -> Void)? = nil
    /// Lidcode uit de browser ("Bewaar in Pasr" op pasr.nl): die nemen we over, zodat de stempels meegaan.
    var memberCode: String? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var preview: BusinessCards.Info?
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?

    private var existing: Card? { cards.first { $0.details.businessCardId == cardID.lowercased() } }

    private var appearance: CardAppearance {
        var a = CardAppearance(storeName: preview?.displayName ?? String(localized: "Stempelkaart"), number: "", format: .qr,
                               colorHex: preview?.color ?? "#6A5CFF", kind: .stamps)
        var d = CardDetails()
        d.stampsTotal = preview?.stampsTotal ?? CardDetails.defaultStamps
        d.stampsCount = 0
        d.reward = preview?.reward
        a.details = d
        return a
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text(existing == nil ? "Een zaak nodigt je uit voor zijn stempelkaart." : "Deze stempelkaart staat al in je Pasr.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    CardFaceView(appearance: existing.map { CardAppearance($0) } ?? appearance, showsCode: false)
                        .aspectRatio(Brand.cardAspect, contentMode: .fit)
                        .frame(maxWidth: 380)
                        .redacted(reason: loading && existing == nil ? .placeholder : [])
                    if let reward = preview?.reward, existing == nil {
                        Label("Beloning: \(reward)", systemImage: "gift.fill").font(.subheadline.weight(.semibold))
                    }
                    if preview?.active == false && existing == nil {
                        Text("Deze stempelkaart is niet meer beschikbaar.").foregroundStyle(Brand.coral)
                    }
                    if let existing {
                        Button {
                            NotificationRouter.pendingCardID = existing.id
                            dismiss()
                            onDone?()
                        } label: {
                            Label("Toon kaart", systemImage: "rectangle.portrait.on.rectangle.portrait").frame(maxWidth: 260).padding(.vertical, 6)
                        }
                        .pasrGlassButton(prominent: true)
                        .tint(Brand.iris)
                    } else {
                        Button { Task { await join() } } label: {
                            HStack {
                                if busy { ProgressView() }
                                Label("Voeg toe aan Pasr", systemImage: "plus")
                            }
                            .frame(maxWidth: 260).padding(.vertical, 6)
                        }
                        .pasrGlassButton(prominent: true)
                        .tint(Brand.iris)
                        .disabled(busy || preview?.active == false)
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center)
                    }
                    Text(memberCode != nil && existing == nil ? "Je stempels uit de browser gaan mee naar Pasr." : "")
                        .font(.footnote.weight(.semibold))
                    Text("Je krijgt een eigen klantcode. Laat de QR-code op de achterkant scannen bij elke aankoop; de zaak zet de stempel en Pasr haalt de stand op. De zaak ziet alleen die code en de stand, niet wie je bent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Stempelkaart")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
            }
            .task {
                preview = await BusinessCards.preview(cardID: cardID)
                loading = false
            }
        }
    }

    private func join() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let card: Card
            if let memberCode, let claimed = try await BusinessCards.claim(code: memberCode, cardID: cardID, preview: preview, in: context) {
                card = claimed
            } else {
                card = try await BusinessCards.join(cardID: cardID, preview: preview, in: context)
            }
            NotificationRouter.pendingCardID = card.id
            dismiss()
            onDone?()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Een binnenkomende join-link, voor `.sheet(item:)`.
struct IncomingBusinessCard: Identifiable {
    let cardID: String
    var memberCode: String? = nil
    var id: String { cardID + (memberCode ?? "") }
}

/// Kaart toevoegen › Stempelkaart (sinds build 43): je maakt zelf geen stempelkaart, je kiest er een van een zaak.
/// Lijst uit pasr_business_directory (gepubliceerde kaarten van goedgekeurde zaken die vindbaar willen zijn), zoeken op
/// zaak, kaart en plaats. Heeft Pasr al toestemming voor je locatie, dan staat wat in de buurt is bovenaan.
struct StampDirectoryView: View {
    let search: String
    var onPick: (String) -> Void

    struct Entry: Identifiable, Hashable {
        let id: String
        let cardName: String
        let business: String
        let city: String
        let logo: String?
        let color: String
        let stampsTotal: Int
        let reward: String
        let distanceKm: Double?

        init?(_ d: [String: Any]) {
            guard let id = d["card_id"] as? String else { return nil }
            self.id = id.lowercased()
            cardName = d["card_name"] as? String ?? ""
            business = d["business_name"] as? String ?? cardName
            city = d["city"] as? String ?? ""
            logo = d["logo"] as? String
            color = (d["color"] as? String).flatMap { $0.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? $0 : nil } ?? "#6A5CFF"
            stampsTotal = (d["stamps_total"] as? NSNumber)?.intValue ?? CardDetails.defaultStamps
            reward = d["reward"] as? String ?? ""
            distanceKm = (d["distance_km"] as? NSNumber)?.doubleValue
        }
    }

    @State private var entries: [Entry] = []
    @State private var loading = true
    @State private var failed = false

    private var nearby: [Entry] { entries.filter { ($0.distanceKm ?? .infinity) <= 25 } }
    private var rest: [Entry] {
        let near = Set(nearby.map(\.id))
        return entries.filter { !near.contains($0.id) }
            .sorted { $0.business.localizedStandardCompare($1.business) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loading && entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if entries.isEmpty {
                empty
            } else {
                if !nearby.isEmpty {
                    header("In de buurt")
                    ForEach(nearby) { row($0) }
                }
                if !rest.isEmpty {
                    if !nearby.isEmpty { header("Alle stempelkaarten") }
                    ForEach(rest) { row($0) }
                }
                Text("Staat jouw zaak er niet tussen? Vraag de ondernemer om Pasr Zakelijk, of scan de QR-code bij de toonbank.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(search.isEmpty ? 0 : 300))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func header(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: CardKind.stamps.symbol).font(.system(size: 34, weight: .semibold)).foregroundStyle(.secondary)
            Text(failed ? "De lijst kon niet worden geladen." : search.isEmpty ? "Nog geen stempelkaarten" : "Geen stempelkaart gevonden")
                .font(.headline)
            Text("Nog geen stempelkaart van jouw zaak? Vraag de ondernemer om Pasr Zakelijk.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if failed {
                Button("Opnieuw", systemImage: "arrow.clockwise") { Task { await load() } }.pasrGlassButton()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func row(_ e: Entry) -> some View {
        Button { onPick(e.id) } label: {
            HStack(spacing: 14) {
                logo(e)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.business).font(.headline).lineLimit(1)
                    Text([e.cardName == e.business ? nil : e.cardName, e.city.isEmpty ? nil : e.city,
                          e.distanceKm.map { String(localized: "\($0.formatted(.number.precision(.fractionLength(0...1)))) km") }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Label("\(e.stampsTotal) stempels: \(e.reward)", systemImage: "gift")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Bekijk de stempelkaart en voeg hem toe"))
    }

    @ViewBuilder private func logo(_ e: Entry) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if let b64 = e.logo, let data = Data(base64Encoded: b64), let image = Image(data: data) {
            image.resizable().scaledToFit().padding(6)
                .frame(width: 46, height: 46).background(Color(hex: e.color), in: shape)
        } else {
            Text(String(e.business.prefix(1)).uppercased())
                .font(.title3.weight(.bold)).foregroundStyle(.white)
                .frame(width: 46, height: 46).background(Color(hex: e.color), in: shape)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        var body: [String: Any] = ["p_limit": 100]
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { body["p_query"] = q }
        // alleen als Pasr al toestemming heeft; hier vragen we er niet om
        if let here = await NearbyStores.shared.currentLocation(maxAge: 900) {
            body["p_lat"] = here.coordinate.latitude
            body["p_lng"] = here.coordinate.longitude
        }
        do {
            let json = try await AccountService.shared.publicRPC("pasr_business_directory", body: body)
            entries = ((json as? [[String: Any]]) ?? []).compactMap(Entry.init)
            failed = false
        } catch {
            failed = entries.isEmpty
        }
    }
}
