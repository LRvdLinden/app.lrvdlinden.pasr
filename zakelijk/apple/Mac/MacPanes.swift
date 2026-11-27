import SwiftUI

// Panelen van de Mac-app die op iOS onderdeel zijn van het tabblad Acties of Overzicht.
// Ze gebruiken dezelfde lijsten, editors en API's als de iOS-app.

/// Vandaag: cijfers van vandaag, het eerstvolgende event en wat er te doen is (zelfde gegevens als de widgets).
struct MacTodayPane: View {
    let business: Business
    var go: (ZakelijkSection) -> Void
    @State private var snapshot: WidgetSnapshot.Business?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MacTodayMetrics(today: snapshot?.today)
                    HStack(alignment: .top, spacing: 18) {
                        MacEventCard(event: snapshot?.event) { go(.tickets) }
                        MacTodoCard(items: snapshot?.todo ?? [], loading: loading && snapshot == nil) { go($0.section) }
                    }
                    MacQuickActions(go: go)
                }
                .padding(24)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg)
            .navigationTitle("Vandaag")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await reload(force: true) } } label: { Label("Ververs", systemImage: "arrow.clockwise") }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(loading)
                }
            }
            .task(id: business.id) { await reload(force: false) }
        }
    }

    @MainActor private func reload(force: Bool) async {
        loading = true
        defer { loading = false }
        snapshot = WidgetStore.load()?.businesses.first { $0.id == business.id }
        if force { await BusinessStore.shared.load() }
        await WidgetSync.refresh(force: force || snapshot == nil)
        snapshot = WidgetStore.load()?.businesses.first { $0.id == business.id } ?? snapshot
    }
}

private struct MacTodayMetrics: View {
    let today: WidgetSnapshot.Today?

    var body: some View {
        CardBox(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Vandaag").font(.headline)
                HStack(spacing: 24) {
                    metric(today?.stamps, "Stempels", "seal.fill", Theme.iris)
                    metric(today?.rewards, "Beloningen", "gift.fill", Theme.coral)
                    metric(today?.joins, "Nieuwe leden", "person.badge.plus", Theme.mint)
                    Spacer()
                    MacTrend(values: today?.trend ?? [])
                        .frame(width: 220, height: 56)
                }
            }
        }
    }

    private func metric(_ value: Int?, _ title: LocalizedStringKey, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(color)
            Text(verbatim: value.map { "\($0)" } ?? "–")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
    }
}

/// Stempels van de laatste 7 dagen.
private struct MacTrend: View {
    let values: [Int]

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(index == values.count - 1 ? Theme.iris : Theme.iris.opacity(0.35))
                        .frame(height: max(3, 40 * CGFloat(value) / CGFloat(top)))
                }
            }
            .frame(height: 40, alignment: .bottom)
            Text("7 dagen").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

private struct MacEventCard: View {
    let event: WidgetSnapshot.Event?
    var open: () -> Void

    var body: some View {
        CardBox(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Komend event", systemImage: "ticket").font(.headline)
                if let e = event {
                    Text(verbatim: e.name).font(.title3.weight(.semibold))
                    Text(verbatim: TKFormat.eventLine(e.startsAt, e.endsAt)).foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        LabeledContent("Aangemeld") { Text(verbatim: "\(e.registered)/\(e.capacity)").monospacedDigit() }
                        LabeledContent("Binnen") { Text(verbatim: "\(e.checkedIn)").monospacedDigit() }
                    }
                    ProgressView(value: Double(min(e.registered, max(e.capacity, 1))), total: Double(max(e.capacity, 1)))
                        .tint(Theme.iris)
                } else {
                    Text("Geen komende events").foregroundStyle(.secondary)
                }
                Button("Naar Tickets", action: open).buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MacTodoCard: View {
    let items: [WidgetSnapshot.TodoItem]
    let loading: Bool
    var open: (WidgetSnapshot.TodoItem) -> Void

    var body: some View {
        CardBox(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Te doen", systemImage: "checklist").font(.headline)
                if loading {
                    ProgressView()
                } else if items.isEmpty {
                    Label("Niets te doen", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.mint)
                } else {
                    ForEach(items) { item in
                        Button { open(item) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.kind == .invite ? "person.3.fill"
                                      : item.kind == .expiring ? "clock.badge.exclamationmark.fill" : "pencil.circle.fill")
                                    .foregroundStyle(item.kind == .invite ? Theme.iris : item.kind == .expiring ? Theme.amber : Theme.muted)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: item.title).lineLimit(1)
                                    Text(verbatim: item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if let date = item.date, item.kind != .draft {
                                    Text(date, format: .dateTime.day().month(.abbreviated)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MacQuickActions: View {
    var go: (ZakelijkSection) -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            Button { openWindow(id: MacWindows.scanner) } label: { Label("Scannen", systemImage: "qrcode.viewfinder") }
                .buttonStyle(.borderedProminent)
            Button { go(.stempelkaarten) } label: { Label("Stempelkaarten", systemImage: "rectangle.stack") }
            Button { go(.inzichten) } label: { Label("Inzichten", systemImage: "chart.bar.xaxis") }
            Button { go(.promotiemateriaal) } label: { Label("Promotiemateriaal", systemImage: "photo.on.rectangle") }
        }
        .controlSize(.large)
    }
}

/// Klantenkaarten: dezelfde lijst en editors als onder Acties op iOS.
struct MacMemberCardsPane: View {
    let business: Business
    @State private var newMemberCard = false
    @State private var editingMember: MemberCard?
    @State private var sharingMember: MemberCard?
    @State private var newEvent = false
    @State private var openedEvent: TicketEvent?
    @State private var reload = 0

    var body: some View {
        NavigationStack {
            Form {
                MemberCardsSection(business: business, reload: reload, onCreate: { newMemberCard = true },
                                   onEdit: { editingMember = $0 }, onShare: { sharingMember = $0 })
            }
            .formStyle(.grouped)
            .navigationTitle("Klantenkaarten")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { reload += 1 } label: { Label("Ververs", systemImage: "arrow.clockwise") }
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
            .modifier(TKSheets(business: business, newEvent: $newEvent, openedEvent: $openedEvent, newMemberCard: $newMemberCard,
                               editingMember: $editingMember, sharingMember: $sharingMember, reload: $reload))
        }
    }
}

/// Tickets: dezelfde lijst en editors als onder Acties op iOS.
struct MacTicketsPane: View {
    let business: Business
    @State private var newMemberCard = false
    @State private var editingMember: MemberCard?
    @State private var sharingMember: MemberCard?
    @State private var newEvent = false
    @State private var openedEvent: TicketEvent?
    @State private var reload = 0

    var body: some View {
        NavigationStack {
            Form {
                TicketEventsSection(business: business, reload: reload, onCreate: { newEvent = true }, onOpen: { openedEvent = $0 })
            }
            .formStyle(.grouped)
            .navigationTitle("Tickets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { reload += 1 } label: { Label("Ververs", systemImage: "arrow.clockwise") }
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
            .modifier(TKSheets(business: business, newEvent: $newEvent, openedEvent: $openedEvent, newMemberCard: $newMemberCard,
                               editingMember: $editingMember, sharingMember: $sharingMember, reload: $reload))
        }
    }
}

/// Beloningen: kies een stempelkaart en stel acties en beloningen in (LoyaltyProgramView).
struct MacRewardsPane: View {
    let business: Business
    @State private var cardID: String?

    var body: some View {
        if business.cards.isEmpty {
            ContentUnavailableView {
                Label("Nog geen stempelkaart", systemImage: "rectangle.stack.badge.plus")
            } description: {
                Text("Een actie of beloning wordt altijd ingesteld op een bestaande stempelkaart.")
            }
        } else {
            HSplitView {
                List(business.cards, selection: $cardID) { card in
                    Label { Text(verbatim: card.name) } icon: {
                        Circle().fill(Color(hex: card.color)).frame(width: 12, height: 12)
                    }
                    .tag(card.id)
                }
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
                Group {
                    if let card = business.cards.first(where: { $0.id == cardID }) {
                        LoyaltyProgramView(card: card).id(card.id)
                    } else {
                        Text("Kies de stempelkaart voor de actie").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 420)
            }
            .navigationTitle("Beloningen")
            .onAppear { if cardID == nil { cardID = business.cards.first?.id } }
        }
    }
}

/// Zoeksuggesties (⌘F): onderdelen van de app, stempelkaarten, events en klantenkaarten.
struct MacSearchResults: View {
    struct Pick {
        let section: ZakelijkSection
    }

    let business: Business
    let query: String
    var pick: (Pick) -> Void
    @State private var events: [TicketEvent] = []
    @State private var memberCards: [MemberCard] = []

    private var q: String { query.trimmingCharacters(in: .whitespaces) }

    private func matches(_ text: String) -> Bool { !q.isEmpty && text.localizedCaseInsensitiveContains(q) }

    var body: some View {
        Group {
            ForEach(ZakelijkSection.allCases.filter { matches($0.localizedName) && (business.isOwner || $0 == .scannen || $0 == .instellingen) }) { s in
                Button { pick(Pick(section: s)) } label: { Label(s.title, systemImage: s.symbol) }
            }
            if business.isOwner {
                ForEach(business.cards.filter { matches($0.name) }) { card in
                    Button { pick(Pick(section: .stempelkaarten)) } label: {
                        Label { Text(verbatim: card.name) } icon: { Image(systemName: "rectangle.stack") }
                    }
                }
                ForEach(events.filter { matches($0.name) }) { e in
                    Button { pick(Pick(section: .tickets)) } label: {
                        Label { Text(verbatim: e.name) } icon: { Image(systemName: "ticket") }
                    }
                }
                ForEach(memberCards.filter { matches($0.name) }) { c in
                    Button { pick(Pick(section: .klantenkaarten)) } label: {
                        Label { Text(verbatim: c.name) } icon: { Image(systemName: "barcode") }
                    }
                }
            }
        }
        .task(id: business.id) {
            guard business.isOwner else { return }
            events = (try? await TKAPI.events(business: business.id)) ?? []
            memberCards = (try? await TKAPI.memberCards(business: business.id)) ?? []
        }
    }
}
