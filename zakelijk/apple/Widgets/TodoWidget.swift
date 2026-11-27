import WidgetKit
import SwiftUI

/// "Te doen": open uitnodigingen voor gezamenlijke acties, concepten en aflopende codes en kortingsperiodes.
struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "zakelijk.tedoen", intent: SelectBusinessIntent.self, provider: ZakelijkProvider()) { entry in
            TodoWidgetView(entry: entry)
                .zakelijkWidgetBackground()
        }
        .configurationDisplayName("Te doen")
        .description("Uitnodigingen voor gezamenlijke acties, concepten en codes of kortingsperiodes die bijna aflopen.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodoWidgetView: View {
    let entry: ZakelijkEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemLarge ? 7 : 3 }

    var body: some View {
        Group {
            if let b = entry.business {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(title: "Te doen", business: b.name, symbol: "checklist")
                    if b.todo.isEmpty {
                        Spacer(minLength: 0)
                        Label("Niets te doen", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(WidgetPalette.mint)
                        Text("Geen uitnodigingen, concepten of aflopende acties.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    } else {
                        ForEach(b.todo.prefix(limit)) { item in
                            Link(destination: ZakelijkLink.url(item.section, business: b.id, item: item.item)) {
                                TodoRow(item: item)
                            }
                        }
                        Spacer(minLength: 0)
                        if b.todo.count > limit {
                            Text(String(format: String(localized: "en nog %lld"), b.todo.count - limit))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                WidgetEmptyView()
            }
        }
        .widgetURL(ZakelijkLink.url(.vandaag, business: entry.business?.id))
    }
}

private struct TodoRow: View {
    let item: WidgetSnapshot.TodoItem

    private var symbol: String {
        switch item.kind {
        case .invite: "person.3.fill"
        case .draft: "pencil.circle.fill"
        case .expiring: "clock.badge.exclamationmark.fill"
        }
    }

    private var color: Color {
        switch item.kind {
        case .invite: WidgetPalette.iris
        case .draft: .secondary
        case .expiring: WidgetPalette.amber
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(verbatim: item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let date = item.date, item.kind != .draft {
                Text(date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.kind == .expiring ? WidgetPalette.amber : Color.secondary)
            }
        }
    }
}
