import WidgetKit
import SwiftUI
import AppIntents

// Basis van de widgets van Pasr Zakelijk (iOS en macOS): de zaakkeuze, de timeline uit de cache van de app en de kleuren.

// MARK: Zaak kiezen (widget bewerken)

struct BusinessEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Zaak"
    static let defaultQuery = BusinessQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct BusinessQuery: EntityQuery {
    private var all: [BusinessEntity] {
        (WidgetStore.load()?.businesses ?? []).map { BusinessEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [BusinessEntity.ID]) async throws -> [BusinessEntity] {
        all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BusinessEntity] { all }

    func defaultResult() async -> BusinessEntity? { all.first }
}

struct SelectBusinessIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Kies een zaak"
    static let description = IntentDescription("Welke zaak deze widget laat zien.")

    @Parameter(title: "Zaak")
    var business: BusinessEntity?
}

// MARK: Timeline

struct ZakelijkEntry: TimelineEntry {
    let date: Date
    let business: WidgetSnapshot.Business?
    let updatedAt: Date?
    /// Nog nooit gegevens van de app (niet ingelogd of de app nog niet geopend).
    var isEmpty: Bool { business == nil }
}

struct ZakelijkProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ZakelijkEntry {
        ZakelijkEntry(date: .now, business: WidgetSnapshot.placeholder.businesses.first, updatedAt: .now)
    }

    func snapshot(for configuration: SelectBusinessIntent, in context: Context) async -> ZakelijkEntry {
        let entry = entry(for: configuration)
        // in de widgetgalerie een voorbeeld als de app nog niets heeft bewaard
        return entry.isEmpty && context.isPreview ? placeholder(in: context) : entry
    }

    func timeline(for configuration: SelectBusinessIntent, in context: Context) async -> Timeline<ZakelijkEntry> {
        // de app ververst de widgets na elk laden; daarnaast elk half uur opnieuw lezen (nieuwe dag, aflopende items)
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: SelectBusinessIntent) -> ZakelijkEntry {
        let snapshot = WidgetStore.load()
        var business = snapshot?.business(configuration.business?.id)
        // cijfers van een eerdere dag tellen niet als "vandaag"
        if var b = business, let updated = snapshot?.updatedAt, !Calendar.current.isDateInToday(updated) {
            b.today = WidgetSnapshot.Today(stamps: 0, rewards: 0, joins: 0, trend: Array(b.today.trend.dropFirst()) + [0],
                                           lastWeekStamps: nil)
            business = b
        }
        return ZakelijkEntry(date: .now, business: business, updatedAt: snapshot?.updatedAt)
    }
}

// MARK: Stijl

enum WidgetPalette {
    static let iris = Color(red: 0x6A / 255, green: 0x5C / 255, blue: 0xFF / 255)
    static let coral = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x57 / 255)
    static let mint = Color(red: 0x2E / 255, green: 0xD3 / 255, blue: 0xA6 / 255)
    static let amber = Color(red: 0xFF / 255, green: 0xB5 / 255, blue: 0x47 / 255)
}

/// Kop van elke widget: zaaknaam met het merkteken.
struct WidgetHeader: View {
    let title: LocalizedStringKey
    let business: String?
    var symbol = "seal.fill"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.iris)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(WidgetPalette.iris)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let business {
                Text(verbatim: business)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Zonder gegevens: vraag om de app te openen.
struct WidgetEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "seal.fill").foregroundStyle(WidgetPalette.iris)
            Text("Open Pasr Zakelijk")
                .font(.headline)
            Text("Log in en open de app; daarna zie je hier je cijfers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    /// Achtergrond van de widget (verplicht vanaf iOS 17 / macOS 14).
    func zakelijkWidgetBackground() -> some View {
        containerBackground(for: .widget) {
            LinearGradient(colors: [WidgetPalette.iris.opacity(0.10), WidgetPalette.coral.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

@main
struct PasrZakelijkWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        EventWidget()
        TodoWidget()
    }
}
