import WidgetKit
import SwiftUI

/// "Komend event": het eerstvolgende gepubliceerde event met aangemeld en binnen.
struct EventWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "zakelijk.event", intent: SelectBusinessIntent.self, provider: ZakelijkProvider()) { entry in
            EventWidgetView(entry: entry)
                .zakelijkWidgetBackground()
        }
        .configurationDisplayName("Komend event")
        .description("Je eerstvolgende event met het aantal aanmeldingen en wie er binnen is.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct EventWidgetView: View {
    let entry: ZakelijkEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let b = entry.business {
                if let e = b.event {
                    content(e, business: b)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetHeader(title: "Komend event", business: family == .systemSmall ? nil : b.name, symbol: "ticket.fill")
                        Spacer(minLength: 0)
                        Text("Geen komende events")
                            .font(.headline)
                        Text("Maak een gratis event in de app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                WidgetEmptyView()
            }
        }
        .widgetURL(ZakelijkLink.url(.tickets, business: entry.business?.id, item: entry.business?.event?.id))
    }

    private func content(_ e: WidgetSnapshot.Event, business: WidgetSnapshot.Business) -> some View {
        let running = e.startsAt <= entry.date && e.endsAt > entry.date
        return VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Komend event", business: family == .systemSmall ? nil : business.name, symbol: "ticket.fill")
            Text(verbatim: e.name)
                .font(.headline)
                .lineLimit(family == .systemSmall ? 2 : 1)
            Group {
                if running {
                    Text("Nu bezig")
                        .foregroundStyle(WidgetPalette.mint)
                } else {
                    Text(e.startsAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 14) {
                counter(e.registered, of: e.capacity, "Aangemeld", WidgetPalette.iris)
                counter(e.checkedIn, of: max(e.registered, 1), "Binnen", WidgetPalette.mint)
            }
            if family != .systemSmall {
                ProgressView(value: Double(min(e.registered, max(e.capacity, 1))), total: Double(max(e.capacity, 1)))
                    .tint(WidgetPalette.iris)
                Text(String(format: String(localized: "%lld plekken over"), max(0, e.capacity - e.registered)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func counter(_ value: Int, of total: Int, _ title: LocalizedStringKey, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(value)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                Text(verbatim: "/\(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
