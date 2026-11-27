import WidgetKit
import SwiftUI

/// "Vandaag": stempels, beloningen en nieuwe leden van vandaag, met de trend van de laatste 7 dagen.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "zakelijk.vandaag", intent: SelectBusinessIntent.self, provider: ZakelijkProvider()) { entry in
            TodayWidgetView(entry: entry)
                .zakelijkWidgetBackground()
        }
        .configurationDisplayName("Vandaag")
        .description("Stempels, beloningen en nieuwe leden van vandaag, met de trend van deze week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    let entry: ZakelijkEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let b = entry.business {
                if family == .systemSmall { small(b) } else { medium(b) }
            } else {
                WidgetEmptyView()
            }
        }
        .widgetURL(ZakelijkLink.url(.vandaag, business: entry.business?.id))
    }

    private func small(_ b: WidgetSnapshot.Business) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Vandaag", business: nil)
            Spacer(minLength: 0)
            Text(verbatim: "\(b.today.stamps)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Text("stempels")
                TrendArrow(today: b.today)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Label { Text(verbatim: "\(b.today.rewards)") } icon: { Image(systemName: "gift.fill").foregroundStyle(WidgetPalette.coral) }
                Label { Text(verbatim: "\(b.today.joins)") } icon: { Image(systemName: "person.badge.plus").foregroundStyle(WidgetPalette.mint) }
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ b: WidgetSnapshot.Business) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Vandaag", business: b.name)
            HStack(alignment: .bottom, spacing: 14) {
                metric(b.today.stamps, "Stempels", "seal.fill", WidgetPalette.iris)
                metric(b.today.rewards, "Beloningen", "gift.fill", WidgetPalette.coral)
                metric(b.today.joins, "Nieuwe leden", "person.badge.plus", WidgetPalette.mint)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 8) {
                TrendBars(values: b.today.trend)
                    .frame(height: 34)
                VStack(alignment: .trailing, spacing: 2) {
                    TrendArrow(today: b.today)
                    Text("7 dagen").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metric(_ value: Int, _ title: LocalizedStringKey, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color)
            Text(verbatim: "\(value)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pijl t.o.v. dezelfde dag vorige week.
struct TrendArrow: View {
    let today: WidgetSnapshot.Today

    var body: some View {
        if let last = today.lastWeekStamps {
            let up = today.stamps >= last
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(up ? WidgetPalette.mint : WidgetPalette.coral)
                .accessibilityLabel(Text(up ? "Meer dan vorige week" : "Minder dan vorige week"))
        }
    }
}

/// Staafjes van de laatste 7 dagen (vandaag in de accentkleur).
struct TrendBars: View {
    let values: [Int]

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index == values.count - 1 ? WidgetPalette.iris : WidgetPalette.iris.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, 34 * CGFloat(value) / CGFloat(top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
