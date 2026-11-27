import SwiftUI

// MARK: Groep tickets (zelfde evenement, zelfde dag) in de stapel en vooraan
//
// Zie Shared/Model/TicketGroups.swift voor de groepeersleutel.

/// DE plek voor de weergave van een ticket in een groep: TicketFaceView (stapel: `front` op kaartformaat, vooraan
/// met de code: `page`, het hoge ticket met QR-code en Route/Informatie).
enum TicketGroupFace {
    /// Hoogte van een hoog ticket (`page`) bij deze breedte; de pager heeft een vaste hoogte nodig.
    static func pageHeight(for width: CGFloat) -> CGFloat { 430 + min(width - 40, 230) }   // kop + golf + QR-deel + knoppen

    /// Voorkant in de stapel (zonder code).
    @ViewBuilder static func front(_ appearance: CardAppearance) -> some View {
        TicketFaceView(appearance: appearance, layout: .front)
    }

    /// Eén ticket vooraan, met de code (`angle` blijft voor de aanroepers; een ticket draait niet om).
    @ViewBuilder static func page(_ card: Card, angle: Double) -> some View {
        TicketFaceView(card: card)
    }
}

/// Groep in de stapel: het eerste ticket met de naam van het evenement, twee randjes erachter (zoals een stapeltje
/// passen in Wallet) en "3 tickets".
struct TicketGroupStackFace: View {
    let item: CardStackItem

    var body: some View {
        var appearance = CardAppearance(item.first)
        appearance.storeName = item.title
        appearance.isFavorite = item.cards.contains(where: \.isFavorite)
        return ZStack(alignment: .top) {
            // randjes van de tickets erachter
            ForEach(0..<min(item.cards.count - 1, 2), id: \.self) { i in
                let level = CGFloat(i + 1)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: item.cards[min(i + 1, item.cards.count - 1)].colorHex).opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .padding(.horizontal, 10 * level)
                    .offset(y: -5 * level)
                    .zIndex(-Double(i + 1))
            }
            TicketGroupFace.front(appearance)
        }
        .overlay(alignment: .top) {
            Label(item.countText, systemImage: "ticket.fill")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .offset(y: -12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(item.title), \(item.countText)"))
    }
}

/// Vooraan: horizontaal vegen tussen de tickets van de groep, met paginapuntjes en "1 van 3". Elk ticket heeft zijn
/// eigen code; de knoppen eronder horen bij het ticket dat je ziet.
struct TicketGroupPager: View {
    let cards: [Card]
    @Binding var page: UUID
    let angle: Double
    let width: CGFloat

    private var index: Int { cards.firstIndex { $0.id == page } ?? 0 }

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                    TicketGroupFace.page(card, angle: angle)
                        .frame(width: width)
                        .frame(height: TicketGroupFace.pageHeight(for: width), alignment: .top)
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 16)
                        .padding(.vertical, 30)
                        .frame(maxWidth: .infinity)
                        .tag(card.id)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(Text("Ticket \(i + 1) van \(cards.count): \(card.storeName)"))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: TicketGroupFace.pageHeight(for: width) + 60)

            indicator
        }
    }

    /// Puntjes en "1 van 3"; met VoiceOver omhoog/omlaag vegen om van ticket te wisselen.
    private var indicator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                ForEach(cards) { card in
                    Circle()
                        .fill(card.id == page ? Color.white : Color.white.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }
            Text("\(index + 1) van \(cards.count)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(cards[index].storeName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .animation(.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ticket \(index + 1) van \(cards.count): \(cards[index].storeName)"))
        .accessibilityHint(Text("Veeg omhoog of omlaag voor het volgende of vorige ticket"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if index + 1 < cards.count { withAnimation { page = cards[index + 1].id } }
            case .decrement: if index > 0 { withAnimation { page = cards[index - 1].id } }
            @unknown default: break
            }
        }
    }
}
