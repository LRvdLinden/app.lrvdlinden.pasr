import SwiftUI
import SwiftData

/// Instellingen › Tijdelijk gedeeld: wat ik tijdelijk heb gedeeld (met stoppen en opnieuw versturen) en wat
/// anderen tijdelijk met mij hebben gedeeld.
struct TempSharesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil && $0.shareToken != nil }) private var received: [Card]
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var sent: [TempShare.Sent] = []
    @State private var stopping: TempShare.Sent?
    @State private var error: String?
    @State private var activity: ActivityItems?

    private var active: [TempShare.Sent] { sent.filter(\.isActive).sorted { $0.until < $1.until } }
    private var ended: [TempShare.Sent] { sent.filter { !$0.isActive }.sorted { $0.until > $1.until } }

    var body: some View {
        // elke 30 seconden opnieuw, zodat "nog 5 min" en verlopen kloppen
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Form {
                Section {
                    VStack(spacing: 12) {
                        FanIcon(size: 72)
                        Text("Kaarten even uitlenen").font(.title3.bold())
                        Text("Bij Deel kies je Tijdelijk en tot wanneer. Na het einde werkt de kaart bij de ander niet meer.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section {
                    if active.isEmpty {
                        Text("Je deelt nu niets tijdelijk.").foregroundStyle(.secondary)
                    }
                    ForEach(active) { item in
                        sentRow(item)
                            .swipeActions {
                                Button("Stop", role: .destructive) { stopping = item }
                                Button("Verstuur") { resend(item) }.tint(Brand.iris)
                            }
                    }
                } header: {
                    Text("Door jou gedeeld")
                } footer: {
                    Text(error ?? String(localized: "Veeg naar links om te stoppen of de link opnieuw te versturen. Stop je, dan werkt de kaart bij de ander direct niet meer."))
                        .foregroundStyle(error == nil ? Color.secondary : Brand.coral)
                }

                if !ended.isEmpty {
                    Section("Afgelopen") {
                        ForEach(ended) { item in sentRow(item) }
                    }
                }

                Section {
                    if received.isEmpty {
                        Text("Er is niets tijdelijk met je gedeeld.").foregroundStyle(.secondary)
                    }
                    ForEach(received.alphabetical()) { card in
                        HStack(spacing: 12) {
                            CardThumb(appearance: CardAppearance(card))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.storeName)
                                status(until: card.sharedUntil, ended: card.isShareExpired, revoked: card.shareRevoked)
                            }
                        }
                        .swipeActions {
                            Button("Verwijder", role: .destructive) {
                                card.deletedAt = .now
                                try? context.save()
                            }
                        }
                    }
                } header: {
                    Text("Met jou gedeeld")
                } footer: {
                    Text("Verlopen kaarten kun je verwijderen; ze werken niet meer.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Brand.ink.ignoresSafeArea())
        }
        .navigationTitle("Tijdelijk gedeeld")
        .onAppear { sent = TempShare.allSent() }
        .refreshable {
            await TempShare.refreshStatuses(in: context)
            sent = TempShare.allSent()
        }
        .confirmationDialog(Text("Delen van \(stopping?.storeName ?? "") stoppen?"),
                            isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
                            titleVisibility: .visible) {
            Button("Stop met delen", role: .destructive) {
                if let item = stopping { Task { await stop(item) } }
                stopping = nil
            }
        } message: {
            Text("De kaart werkt bij de ander direct niet meer.")
        }
        #if canImport(UIKit)
        .sheet(item: $activity) { items in
            ActivityView(items: items.items).ignoresSafeArea().presentationDetents([.medium, .large])
        }
        #endif
    }

    private func sentRow(_ item: TempShare.Sent) -> some View {
        let card = cards.first { $0.id == item.cardID }
        return HStack(spacing: 12) {
            if let card {
                CardThumb(appearance: CardAppearance(card))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.gray.opacity(0.4)).frame(width: 46, height: 29)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.storeName)
                status(until: item.until, ended: !item.isActive, revoked: item.revoked)
            }
        }
    }

    @ViewBuilder private func status(until: Date?, ended: Bool, revoked: Bool) -> some View {
        Group {
            if revoked {
                Text("Gestopt")
            } else if let until, ended {
                Text("Verlopen op \(until.formatted(date: .abbreviated, time: .shortened))")
            } else if let until {
                Text("Tot \(until.formatted(date: .abbreviated, time: .shortened)) · \(until.formatted(.relative(presentation: .named)))")
            }
        }
        .font(.footnote)
        .foregroundStyle(ended || revoked ? Brand.coral : .secondary)
    }

    private func stop(_ item: TempShare.Sent) async {
        do {
            try await TempShare.stop(item)
            sent = TempShare.allSent()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resend(_ item: TempShare.Sent) {
        let date = item.until.formatted(date: .abbreviated, time: .shortened)
        let text = String(localized: "Je mag mijn \(item.storeName)-kaart gebruiken tot \(date). Open de link om hem aan Pasr toe te voegen:") + "\n" + item.url.absoluteString
        activity = ActivityItems(items: [text])
    }
}

/// Kleine kaart in een lijst.
private struct CardThumb: View {
    let appearance: CardAppearance
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: appearance.colorHex))
            .frame(width: 46, height: 29)
            .overlay {
                if let data = appearance.logoData {
                    StoreLogoMark(data: data, style: appearance.logoStyle, height: 16, maxWidth: 38)
                } else {
                    Text(appearance.monogram).font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.onCard(appearance.colorHex))
                }
            }
            .opacity(appearance.tempExpired ? 0.5 : 1)
    }
}

/// Icoon met drie kaarten als een waaier, in de stijl van de andere rijen in Instellingen.
struct FanIcon: View {
    var size: CGFloat = 29

    var body: some View {
        let card = size * 0.46
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#FF8A78"), Brand.coral], startPoint: .topLeading, endPoint: .bottomTrailing))
            ForEach(Array([Brand.mint, Brand.iris, Color.white].enumerated()), id: \.offset) { i, color in
                RoundedRectangle(cornerRadius: card * 0.14, style: .continuous)
                    .fill(color)
                    .frame(width: card, height: card / 1.586)
                    .overlay(
                        RoundedRectangle(cornerRadius: card * 0.14, style: .continuous)
                            .strokeBorder(.black.opacity(0.12), lineWidth: max(0.5, size / 60))
                    )
                    .rotationEffect(.degrees(Double(i - 1) * 22), anchor: .bottom)
                    .offset(y: -size * 0.02)
                    .shadow(color: .black.opacity(0.2), radius: size / 40, y: size / 60)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
