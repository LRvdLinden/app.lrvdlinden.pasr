import SwiftUI
import Charts

/// Overzicht (eigenaar): cijfers per dag in Homey Insights-stijl, leden per kaart en het logboek.
struct OverviewView: View {
    let business: Business

    enum Metric: String, CaseIterable, Identifiable {
        case stamps, rewards, joins
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .stamps: "Stempels"
            case .rewards: "Beloningen"
            case .joins: "Nieuwe leden"
            }
        }
        var icon: String {
            switch self {
            case .stamps: "seal.fill"
            case .rewards: "gift.fill"
            case .joins: "person.badge.plus"
            }
        }
        var color: Color {
            switch self {
            case .stamps: Theme.mint
            case .rewards: Theme.coral
            case .joins: Theme.iris
            }
        }
        /// Eenheid achter de waarde en bovenaan de Y-as.
        var unit: String {
            switch self {
            case .stamps: String(localized: "stempels")
            case .rewards: String(localized: "beloningen")
            case .joins: String(localized: "leden")
            }
        }
        func value(_ d: DayStat) -> Int {
            switch self {
            case .stamps: d.stamps
            case .rewards: d.rewards
            case .joins: d.joins
            }
        }
    }

    @State private var days = 30
    @State private var metric: Metric = .stamps
    @State private var stats: [DayStat] = []
    @State private var previous: [DayStat] = []
    @State private var members: Int?
    @State private var loyalty: [String: Any] = [:]
    @State private var coupons: [[String: Any]] = []
    @State private var promoCodes: [[String: Any]] = []
    @State private var tkEvents: [TicketEvent] = []
    @State private var tkCards: [MemberCard] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: MetricPoint?
    /// Vergelijkkiezer: false = deze periode, true = de vorige.
    @State private var showPrevious = false

    /// De server geeft hoogstens 366 dagen terug: bij een jaar is er geen vorige periode.
    private var hasPrevious: Bool { days * 2 <= 366 }
    private var shown: [DayStat] { showPrevious && hasPrevious ? previous : stats }

    private var points: [MetricPoint] { shown.map { MetricPoint(date: $0.day, value: Double(metric.value($0))) } }
    private var total: Int { shown.reduce(0) { $0 + metric.value($1) } }
    private var previousTotal: Int { previous.reduce(0) { $0 + metric.value($1) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    chartCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    HStack(spacing: 10) {
                        kpi("Stempels", stats.reduce(0) { $0 + $1.stamps }, Theme.mint)
                        kpi("Beloningen", stats.reduce(0) { $0 + $1.rewards }, Theme.coral)
                        kpi("Leden", members ?? business.cards.reduce(0) { $0 + $1.members }, Theme.iris)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                TKOverviewSection(events: tkEvents, cards: tkCards)
                Section("Zakelijke acties") {
                    LabeledContent("Stempelkaarten online") { Text("\(business.cards.filter(\.published).count)") }
                    LabeledContent("Actieve kortingscoupons") {
                        Text(String(coupons.filter { coupon in
                            guard coupon["public"] as? Bool == true else { return false }
                            let expiry = (coupon["ends_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                            return (expiry ?? .distantPast) > .now
                        }.count))
                    }
                    LabeledContent("Actieve actiecodes") {
                        Text(String(promoCodes.filter { code in
                            (code["active"] as? Bool ?? false) &&
                            ((code["used_count"] as? NSNumber)?.intValue ?? 0) <
                            ((code["max_uses"] as? NSNumber)?.intValue ?? 0)
                        }.count))
                    }
                    LabeledContent("Actiecodes gebruikt") {
                        Text("\(promoCodes.reduce(0) { $0 + (($1["used_count"] as? NSNumber)?.intValue ?? 0) })")
                    }
                    Text("Klantbinding, campagnes, vestigingen en samenwerkingen beheer je via de bestaande functies. Deze cijfers komen rechtstreeks uit je zakelijke acties.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !loyalty.isEmpty {
                    Section("Klantenbinding · laatste 30/90 dagen") {
                        insight("Nieuwe klanten (30 dagen)", "members_30d")
                        insight("Terugkerende klanten (90 dagen)", "returning_customers_90d")
                        insight("Tussentijdse beloningen", "milestone_rewards")
                        insight("Kortingsbonnen bewaard", "claimed_coupons")
                        insight("Kortingsbonnen verzilverd", "redeemed_coupons")
                        Text("Cijfers komen van geverifieerde servergebeurtenissen; dit zijn geen omzetbedragen.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.coral) }
                }
                Section("Leden per kaart") {
                    if business.cards.isEmpty {
                        Text("Nog geen kaarten.").foregroundStyle(.secondary)
                    }
                    ForEach(business.cards) { card in
                        NavigationLink {
                            MembersView(card: card)
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: card.color)).frame(width: 12, height: 12)
                                Text(verbatim: card.name)
                                Spacer()
                                Text(verbatim: "\(card.members)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        LogView(business: business)
                    } label: {
                        Label("Logboek", systemImage: "list.bullet.rectangle")
                    }
                } footer: {
                    Text("Elke stempel, inwisseling en ongedaanmaking met wie, wat en wanneer. Het logboek kan niet worden gewist.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Overzicht")
            .toolbar { BusinessPicker() }
            .refreshable { await load() }
            .task(id: days) { await load() }
            .onChange(of: showPrevious) { _, _ in selected = nil }
            .onChange(of: metric) { _, _ in selected = nil }
        }
    }

    private func insight(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: "\((loyalty[key] as? NSNumber)?.intValue ?? 0)")
                .monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func kpi(_ title: LocalizedStringKey, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: "\(value)").font(.system(size: 24, weight: .heavy)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.vertical, 12).padding(.leading, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, style: .continuous).fill(color).frame(width: 3)
        }
        .accessibilityElement(children: .combine)
    }

    /// Grafiekkaart zoals Homey Insights: titel, meetwaarde-pil, kop (periode + waarde), grafiek, periodekiezer
    /// (W · M · K · J) en vergelijkkiezer (deze/vorige periode).
    private var chartCard: some View {
        VStack(spacing: 14) {
            Text(verbatim: business.name).font(.headline)
            Menu {
                Picker("Meetwaarde", selection: $metric) {
                    ForEach(Metric.allCases) { m in Label(m.title, systemImage: m.icon).tag(m) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: metric.icon)
                    Text(metric.title)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.color)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.insightsPill, in: Capsule())
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(periodTitle).font(.title2.weight(.bold))
                    if let s = selected {
                        Text(s.date, format: .dateTime.weekday(.wide).day().month(.wide)).font(.caption).foregroundStyle(.secondary)
                    } else if let first = shown.first?.day, let last = shown.last?.day {
                        Text(verbatim: "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(selected.map { Int($0.value) } ?? total)")
                        .font(.system(size: 30, weight: .heavy).monospacedDigit())
                        .foregroundStyle(metric.color)
                        .contentTransition(.numericText())
                    Text(verbatim: metric.unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(metric.color.opacity(0.6))
                }
                .accessibilityElement(children: .combine)
            }
            ZStack {
                InsightsChart(points: points, unit: metric.unit, color: metric.color,
                              xFormat: days >= 365 ? .dateTime.month(.narrow) : .dateTime.day().month(.narrow),
                              selected: $selected)
                if loading && stats.isEmpty { ProgressView() }
                if !loading && points.allSatisfy({ $0.value == 0 }) {
                    Text("Nog geen gegevens in deze periode").font(.footnote).foregroundStyle(.secondary)
                }
            }
            PillSegments(items: [(7, "W"), (30, "M"), (90, "K"), (365, "J")], selection: $days,
                         spoken: [7: "Week", 30: "Maand", 90: "Kwartaal", 365: "Jaar"])
            if hasPrevious {
                PillSegments(items: [(false, currentLabel), (true, previousLabel)], selection: $showPrevious)
            } else {
                PillSegments(items: [(false, currentLabel)], selection: $showPrevious)
            }
        }
        .padding(18)
        .background(Theme.insightsCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var currentLabel: LocalizedStringKey {
        switch days {
        case 7: "Deze week"
        case 30: "Deze maand"
        case 90: "Dit kwartaal"
        default: "Dit jaar"
        }
    }

    private var previousLabel: LocalizedStringKey {
        switch days {
        case 7: "Vorige week"
        case 30: "Vorige maand"
        case 90: "Vorig kwartaal"
        default: "Vorig jaar"
        }
    }

    private var periodTitle: LocalizedStringKey {
        showPrevious && hasPrevious ? previousLabel : currentLabel
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            // twee periodes ophalen: deze en de vorige (om te vergelijken)
            let span = hasPrevious ? days * 2 : min(days, 366)
            let both = try await BusinessAPI.stats(business: business.id, days: span)
            let filled = Self.fill(both.days, days: span)
            withAnimation {
                previous = hasPrevious ? Array(filled.prefix(days)) : []
                stats = Array(filled.suffix(days))
                if !hasPrevious { showPrevious = false }
                members = both.members
                selected = nil
            }
            error = nil
            if let list = try? await Account.shared.rpc("pasr_business_coupon_list",
                ["p_business": business.id]) as? [[String: Any]] { coupons = list }
            if let list = try? await Account.shared.rpc("pasr_business_promo_list",
                ["p_business": business.id]) as? [[String: Any]] { promoCodes = list }
            if let list = try? await TKAPI.events(business: business.id) { tkEvents = list }
            if let list = try? await TKAPI.memberCards(business: business.id) { tkCards = list }
            if let response = try? await Account.shared.rpc("pasr_business_loyalty_insights",
                ["p_business": business.id]),
                let values = response as? [String: Any] {
                loyalty = values
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Elke dag een waarde (ook 0), zodat de lijn klopt.
    static func fill(_ list: [DayStat], days: Int) -> [DayStat] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
        let today = cal.startOfDay(for: .now)
        var byDay: [Date: DayStat] = [:]
        for d in list { byDay[cal.startOfDay(for: d.day)] = d }
        return (0..<days).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byDay[day] ?? DayStat(day: day)
        }
    }
}

/// Leden van één kaart (alleen de laatste tekens van de code).
struct MembersView: View {
    let card: BusinessCard
    @State private var rows: [MemberRow] = []
    @State private var total = 0
    @State private var loaded = false
    @State private var error: String?
    @State private var search = ""

    private var filtered: [MemberRow] {
        search.isEmpty ? rows : rows.filter { $0.code.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if let error {
                ContentUnavailableView {
                    Label("Laden lukt niet", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Opnieuw proberen") { Task { await load() } }
                }
            } else if loaded && rows.isEmpty {
                ContentUnavailableView("Nog geen leden", systemImage: "person.2",
                                       description: Text("Deel de QR-code of hang de flyer op."))
            }
            if !rows.isEmpty {
                Section {
                    ForEach(filtered) { m in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: m.code).font(.body.monospaced())
                                if let last = m.lastStampAt {
                                    Text("Laatste stempel \(last, style: .relative) geleden").font(.caption).foregroundStyle(.secondary)
                                } else if let created = m.createdAt {
                                    Text("Lid sinds \(created, format: .dateTime.day().month().year())").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(verbatim: "\(m.stamps)/\(card.stampsTotal)").monospacedDigit().font(.headline)
                                if m.rewards > 0 {
                                    Label { Text(verbatim: "\(m.rewards)") } icon: { Image(systemName: "gift") }
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if m.app {
                                Image(systemName: "iphone").foregroundStyle(.secondary).accessibilityLabel(Text("In de app"))
                            }
                        }
                    }
                } footer: {
                    Text(String(format: String(localized: "%lld leden"), total))
                }
            }
        }
        .navigationTitle(Text(verbatim: card.name))
        .searchable(text: $search, prompt: Text("Zoek op code"))
        .refreshable { await load() }
        .task { await load() }
        .overlay { if !loaded && error == nil { ProgressView() } }
    }

    private func load() async {
        do {
            let r = try await BusinessAPI.members(card: card.id)
            rows = r.members
            total = r.total
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

/// Logboek van de zaak (eigenaar). Niet te wissen.
struct LogView: View {
    let business: Business
    @State private var events: [LogEvent] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var search = ""

    private var filtered: [LogEvent] {
        guard !search.isEmpty else { return events }
        return events.filter { "\($0.who) \($0.card) \($0.member) \($0.device ?? "")".localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if let error {
                ContentUnavailableView {
                    Label("Laden lukt niet", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Opnieuw proberen") { Task { await load() } }
                }
            } else if loaded && events.isEmpty {
                ContentUnavailableView("Nog niets gebeurd", systemImage: "list.bullet.rectangle",
                                       description: Text("Hier komt elke stempel en inwisseling te staan."))
            }
            ForEach(filtered) { e in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(e.kind))
                        .foregroundStyle(color(e.kind))
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title(e)).font(.subheadline.weight(.semibold)).strikethrough(e.undone)
                        Text(verbatim: detail(e))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: [who(e), e.device ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let at = e.at {
                        Text(at, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Logboek")
        .searchable(text: $search, prompt: Text("Zoek op medewerker, kaart of code"))
        .refreshable { await load() }
        .task { await load() }
        .overlay { if !loaded && error == nil { ProgressView() } }
    }

    private func load() async {
        do {
            events = try await BusinessAPI.log(business: business.id, limit: 500)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func detail(_ e: LogEvent) -> String {
        var parts: [String] = []
        if !e.card.isEmpty { parts.append(e.card) }
        if !e.member.isEmpty { parts.append("…" + String(e.member.suffix(4))) }
        return parts.joined(separator: " · ")
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "stamp": "seal.fill"
        case "redeem": "gift.fill"
        case "undo": "arrow.uturn.backward.circle.fill"
        case "join": "person.badge.plus"
        case "claim": "arrow.down.app.fill"
        default: "circle"
        }
    }

    private func color(_ kind: String) -> Color {
        switch kind {
        case "stamp": Theme.mint
        case "redeem": Theme.coral
        case "undo": Theme.amber
        default: Theme.iris
        }
    }

    private func title(_ e: LogEvent) -> String {
        switch e.kind {
        case "stamp": e.amount == 1 ? String(localized: "1 stempel") : String(format: String(localized: "%lld stempels"), e.amount)
        case "redeem": String(localized: "Beloning ingewisseld")
        case "undo": String(localized: "Ongedaan gemaakt")
        case "join": String(localized: "Nieuw lid")
        case "claim": String(localized: "Kaart overgezet naar de app")
        default: e.kind
        }
    }

    private func who(_ e: LogEvent) -> String {
        switch e.byRole {
        case "owner": e.who.isEmpty ? String(localized: "Eigenaar") : e.who + " (" + String(localized: "eigenaar") + ")"
        case "staff": e.who.isEmpty ? String(localized: "Medewerker") : e.who
        case "customer": String(localized: "Klant")
        default: e.who
        }
    }
}
