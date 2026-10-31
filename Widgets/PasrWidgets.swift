import WidgetKit
import SwiftUI
import AppIntents

@main
struct PasrWidgets: WidgetBundle {
    var body: some Widget {
        FavoritesWidget()
        MostUsedWidget()
        CardWidget()
    }
}

// MARK: - Favourites (like Klarna's card grid)

struct CardsEntry: TimelineEntry {
    let date: Date
    let cards: [WidgetCard]
}

struct FavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CardsEntry { CardsEntry(date: .now, cards: WidgetCard.preview) }

    func getSnapshot(in context: Context, completion: @escaping (CardsEntry) -> Void) {
        let cards = WidgetStore.favourites()
        completion(CardsEntry(date: .now, cards: cards.isEmpty && context.isPreview ? WidgetCard.preview : cards))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CardsEntry>) -> Void) {
        // The app reloads the widgets whenever a card changes; this is only a fallback.
        completion(Timeline(entries: [CardsEntry(date: .now, cards: WidgetStore.favourites())],
                            policy: .after(.now.addingTimeInterval(6 * 3600))))
    }
}

struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nl.lrvdlinden.pasr.favorites", provider: FavoritesProvider()) { entry in
            FavoritesView(entry: entry)
                .containerBackground(Brand.ink, for: .widget)
        }
        .configurationDisplayName("Favorieten")
        .description("Je favoriete kaarten. Tik op een kaart om de code te tonen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FavoritesView: View {
    let entry: CardsEntry
    @Environment(\.widgetFamily) private var family

    private var layout: (columns: Int, count: Int) {
        switch family {
        case .systemSmall: (2, 4)
        case .systemLarge: (3, 12)
        default: (4, 8)
        }
    }

    var body: some View {
        if entry.cards.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "wallet.pass").font(.title2)
                Text("Voeg kaarten toe in Pasr").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .widgetURL(URL(string: "pasr://wallet"))
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: layout.columns)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(entry.cards.prefix(layout.count)) { card in
                    if family == .systemSmall {
                        CardTile(card: card, compact: true)
                    } else {
                        Link(destination: card.url) { CardTile(card: card, compact: family == .systemMedium) }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: family == .systemLarge ? .top : .center)
            .widgetURL(family == .systemSmall ? entry.cards.first?.url : nil)
        }
    }
}

/// A small card: house colour, logo or letters, and the name.
struct CardTile: View {
    let card: WidgetCard
    var compact = false

    var body: some View {
        let ink = Color.onCard(card.colorHex)
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
                .fill(LinearGradient(colors: [Color.shade(card.colorHex, by: 0.14), Color(hex: card.colorHex),
                                              Color.shade(card.colorHex, by: -0.2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let data = card.logoData, let image = Image(data: data) {
                image.resizable().scaledToFit()
                    .frame(maxWidth: compact ? 34 : 44, maxHeight: compact ? 18 : 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(compact ? 5 : 7)
            } else {
                Text(card.monogram)
                    .font(.system(size: compact ? 11 : 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(compact ? 5 : 7)
            }
            if !compact {
                Text(card.name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 5)
            }
        }
        .aspectRatio(Brand.cardAspect, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
        .accessibilityLabel(Text(card.name))
    }
}

// MARK: - Most used ("top cards")

struct MostUsedProvider: TimelineProvider {
    func placeholder(in context: Context) -> CardsEntry { CardsEntry(date: .now, cards: WidgetCard.preview) }

    func getSnapshot(in context: Context, completion: @escaping (CardsEntry) -> Void) {
        let cards = mostUsed()
        completion(CardsEntry(date: .now, cards: cards.isEmpty && context.isPreview ? WidgetCard.preview : cards))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CardsEntry>) -> Void) {
        completion(Timeline(entries: [CardsEntry(date: .now, cards: mostUsed())],
                            policy: .after(.now.addingTimeInterval(6 * 3600))))
    }

    private func mostUsed() -> [WidgetCard] {
        WidgetStore.load().sorted { $0.score > $1.score }
    }
}

struct MostUsedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nl.lrvdlinden.pasr.mostused", provider: MostUsedProvider()) { entry in
            FavoritesView(entry: entry)
                .containerBackground(Brand.ink, for: .widget)
        }
        .configurationDisplayName("Meest gebruikt")
        .description("De kaarten die je het vaakst gebruikt, vanzelf bijgewerkt.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - One card, with its code

struct CardEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Kaart")
    static var defaultQuery = CardQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ card: WidgetCard) {
        id = card.id
        name = card.name
    }
}

struct CardQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CardEntity] {
        WidgetStore.load().filter { identifiers.contains($0.id) }.map(CardEntity.init)
    }

    func suggestedEntities() async throws -> [CardEntity] {
        WidgetStore.load().map(CardEntity.init)
    }

    func defaultResult() async -> CardEntity? {
        WidgetStore.favourites().first.map(CardEntity.init)
    }
}

struct SelectCardIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kaart kiezen"
    static var description = IntentDescription("Kies welke kaart de widget toont.")

    @Parameter(title: "Kaart")
    var card: CardEntity?

    init() {}
}

struct CardEntry: TimelineEntry {
    let date: Date
    let card: WidgetCard?
}

struct CardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CardEntry { CardEntry(date: .now, card: WidgetCard.preview[0]) }

    func snapshot(for configuration: SelectCardIntent, in context: Context) async -> CardEntry {
        CardEntry(date: .now, card: resolve(configuration) ?? (context.isPreview ? WidgetCard.preview[0] : nil))
    }

    func timeline(for configuration: SelectCardIntent, in context: Context) async -> Timeline<CardEntry> {
        Timeline(entries: [CardEntry(date: .now, card: resolve(configuration))],
                 policy: .after(.now.addingTimeInterval(6 * 3600)))
    }

    private func resolve(_ configuration: SelectCardIntent) -> WidgetCard? {
        let all = WidgetStore.load()
        if let id = configuration.card?.id, let card = all.first(where: { $0.id == id }) { return card }
        return WidgetStore.favourites().first
    }
}

struct CardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "nl.lrvdlinden.pasr.card", intent: SelectCardIntent.self, provider: CardProvider()) { entry in
            CardWidgetView(entry: entry)
        }
        .configurationDisplayName("Kaart")
        .description("Eén kaart met de barcode of QR-code, klaar om te scannen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct CardWidgetView: View {
    let entry: CardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let card = entry.card {
            content(card)
                .widgetURL(card.url)
        } else {
            Text("Kies een kaart")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .containerBackground(Brand.ink, for: .widget)
        }
    }

    @ViewBuilder private func content(_ card: WidgetCard) -> some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text(card.monogram).font(.system(.title3, design: .rounded).weight(.bold))
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(card.name, systemImage: "wallet.pass").font(.headline).lineLimit(1)
                Text("Tik om de code te tonen").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Label(card.name, systemImage: "wallet.pass")
                .containerBackground(.clear, for: .widget)
        case .systemSmall:
            CardFaceView(appearance: card.appearance, showsCode: false, cornerRadius: 0)
                .containerBackground(Color(hex: card.colorHex), for: .widget)
        default:
            CardFaceView(appearance: card.appearance, cornerRadius: 0)
                .containerBackground(Color(hex: card.colorHex), for: .widget)
        }
    }
}
