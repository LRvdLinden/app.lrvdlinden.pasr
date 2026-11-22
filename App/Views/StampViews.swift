import SwiftUI
import SwiftData

/// Onder een stempelkaart die naar voren is gehaald: stempel erbij of eraf met een tik, en bij een volle kaart
/// "Beloning ingewisseld". Een zakelijke kaart volgt de zaak: dan alleen de stand en verversen.
struct StampControls: View {
    @Bindable var card: Card
    var width: CGFloat
    @Environment(\.modelContext) private var context
    @State private var refreshing = false
    @State private var confirmRedeem = false
    @State private var tick = 0

    private var details: CardDetails { card.details }

    var body: some View {
        VStack(spacing: 10) {
            if card.stampsEditable {
                HStack(spacing: 14) {
                    Button { change(-1) } label: {
                        Label("Stempel eraf", systemImage: "minus").labelStyle(.iconOnly).font(.title3).frame(width: 30, height: 30)
                    }
                    .pasrGlassButton()
                    .disabled(details.stampsCountValue == 0)
                    .accessibilityLabel(Text("Stempel eraf"))

                    progress.frame(maxWidth: .infinity)

                    if details.stampsFull {
                        Button { confirmRedeem = true } label: {
                            Label("Ingewisseld", systemImage: "gift.fill").font(.subheadline.weight(.semibold))
                        }
                        .pasrGlassButton(prominent: true)
                        .tint(Brand.mint)
                    } else {
                        Button { change(1) } label: {
                            Label("Stempel erbij", systemImage: "plus").labelStyle(.iconOnly).font(.title3).frame(width: 30, height: 30)
                        }
                        .pasrGlassButton(prominent: true)
                        .tint(Brand.iris)
                        .accessibilityLabel(Text("Stempel erbij"))
                    }
                }
            } else if details.isBusiness {
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
        .sensoryFeedback(.increase, trigger: tick)
        .task(id: card.id) { if details.isBusiness { await refresh() } }
        .confirmationDialog("Beloning ingewisseld?", isPresented: $confirmRedeem, titleVisibility: .visible) {
            Button("Ja, begin een nieuwe kaart") {
                card.redeemStamps()
                saved()
            }
        } message: {
            Text("De stempels gaan terug naar 0 van \(details.stampsTotalValue).")
        }
    }

    private var progress: some View {
        VStack(spacing: 2) {
            Text("\(details.stampsCountValue) van \(details.stampsTotalValue) stempels")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(details.isBusiness ? String(localized: "Stempels zet de zaak · ") + details.stampsProgressText : details.stampsProgressText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private func change(_ delta: Int) {
        let full = card.changeStamps(by: delta)
        if delta > 0 { tick += 1 }
        if full { StampAlerts.cardFull(card) }
        saved()
    }

    private func saved() {
        try? context.save()
        WalletPass.scheduleRefresh(card)
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        if await BusinessCards.refresh(card) { try? context.save() }
    }
}

/// Een join-link of QR-code van een zaak (pasr.nl/zakelijk/kaart/#…): de kaart bekijken en toevoegen.
struct JoinBusinessSheet: View {
    let cardID: String
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
            let card = try await BusinessCards.join(cardID: cardID, preview: preview, in: context)
            NotificationRouter.pendingCardID = card.id
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Een binnenkomende join-link, voor `.sheet(item:)`.
struct IncomingBusinessCard: Identifiable {
    let cardID: String
    var id: String { cardID }
}
