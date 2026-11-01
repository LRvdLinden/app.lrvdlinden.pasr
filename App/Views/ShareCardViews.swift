import SwiftUI
import SwiftData

/// Share a card: as a link (Messages, WhatsApp, mail) or as a QR code the other person scans
/// with their camera. The link opens in their Pasr, or shows the card on pasr.nl without the app.
struct ShareCardSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if let url = CardShare.url(for: card) {
                    Text("Laat de ander deze code scannen met de camera van zijn iPhone, of stuur de link.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    BarcodeView(value: url.absoluteString, format: .qr)
                        .padding(18)
                        .frame(width: 250, height: 250)
                        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    ShareLink(item: url,
                              subject: Text("\(card.storeName) voor Pasr"),
                              message: Text("Hier is de \(card.storeName)-kaart. Open de link om hem aan Pasr toe te voegen."),
                              preview: SharePreview("\(card.storeName) (Pasr)", image: Image(systemName: "wallet.pass"))) {
                        Label("Stuur link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: 260)
                            .padding(.vertical, 6)
                    }
                    .pasrGlassButton(prominent: true)
                    .tint(Brand.iris)

                    Text("Logo's, foto's en notities gaan niet mee. Wie de link heeft, kan de kaart gebruiken.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                } else {
                    Text("Deze kaart kan niet worden gedeeld.").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Deel \(card.storeName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
        }
    }
}

/// Shown when someone opens a shared card link: a preview and one button to add it.
struct ReceiveCardSheet: View {
    let shared: SharedCard
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var angle: Double = 0

    private var alreadyAdded: Bool { cards.contains { $0.number == shared.c && $0.formatRaw == shared.f } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Iemand heeft een kaart met je gedeeld.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                FlipCardView(appearance: shared.appearance, angle: angle)
                    .aspectRatio(Brand.cardAspect, contentMode: .fit)
                    .frame(maxWidth: 380)
                    .padding(.horizontal)
                    .onTapGesture { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { angle = angle == 0 ? 180 : 0 } }

                if alreadyAdded {
                    Label("Deze kaart staat al in je Pasr", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Brand.mint)
                }
                Button {
                    add()
                } label: {
                    Label("Voeg toe aan Pasr", systemImage: "plus")
                        .frame(maxWidth: 260)
                        .padding(.vertical, 6)
                }
                .pasrGlassButton(prominent: true)
                .tint(Brand.iris)
                .disabled(alreadyAdded)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle(shared.n)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { angle = 180 }
            }
        }
    }

    private func add() {
        let card = shared.makeCard()
        card.refreshCodeImage()
        context.insert(card)
        try? context.save()
        let context = context
        Task { await LogoService.fillMissing(in: context) }
        dismiss()
    }
}

/// An incoming shared card, for `.sheet(item:)`.
struct IncomingShare: Identifiable {
    let id = UUID()
    let card: SharedCard
}
