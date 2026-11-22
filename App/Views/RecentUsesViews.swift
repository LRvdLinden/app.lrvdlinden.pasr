import SwiftUI
import SwiftData

/// Teksten voor "Laatst gebruikt": wanneer en waar je een kaart liet zien, en wat je uitgaf.
enum UseFormat {
    static let locale = Locale(identifier: "nl_NL")
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        c.firstWeekday = 2   // week begint op maandag
        return c
    }

    /// Vetgedrukte regel: het filiaal ("PLUS Apeldoorn", alleen op dit apparaat bekend), anders de winkel.
    static func title(_ e: CardEvent, card: Card) -> String {
        e.place ?? (card.storeName.isEmpty ? String(localized: "Getoond") : card.storeName)
    }

    static func money(_ value: Double, card: Card) -> String { CardHistoryFormat.money(value, card.currencyCode) }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// Kort, voor het paneel onder de kaart: "Zojuist", "2 uur geleden", "Gisteren", "Woensdag", "9 november".
    static func when(_ date: Date, now: Date = .now) -> String {
        let cal = calendar
        if now.timeIntervalSince(date) < 60 { return String(localized: "Zojuist") }
        if cal.isDateInToday(date) {
            return capitalized(date.formatted(.relative(presentation: .named).locale(locale)))
        }
        if cal.isDateInYesterday(date) { return String(localized: "Gisteren") }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day, days < 7 {
            return capitalized(date.formatted(.dateTime.weekday(.wide).locale(locale)))
        }
        return dayMonth(date, now: now)
    }

    /// Met tijd, voor de lijst: "Vandaag 16:05", "Woensdag 18:22", "9 november 14:03".
    static func whenWithTime(_ date: Date, now: Date = .now) -> String {
        let cal = calendar
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().locale(locale))
        let day: String
        if cal.isDateInToday(date) { day = String(localized: "Vandaag") }
        else if cal.isDateInYesterday(date) { day = String(localized: "Gisteren") }
        else if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day, days < 7 {
            day = capitalized(date.formatted(.dateTime.weekday(.wide).locale(locale)))
        } else { day = dayMonth(date, now: now) }
        return "\(day) \(time)"
    }

    private static func dayMonth(_ date: Date, now: Date) -> String {
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.day().month(.wide).locale(locale))
                        : date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    /// Kop van een groep in de lijst: "Deze week", "Eerder in november", "Oktober", "September 2025".
    static func group(_ date: Date, now: Date = .now) -> String {
        let cal = calendar
        if let week = cal.dateInterval(of: .weekOfYear, for: now), date >= week.start { return String(localized: "Deze week") }
        if cal.isDate(date, equalTo: now, toGranularity: .month) {
            return String(localized: "Eerder in \(date.formatted(.dateTime.month(.wide).locale(locale)))")
        }
        let month = cal.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.wide).locale(locale))
            : date.formatted(.dateTime.month(.wide).year().locale(locale))
        return capitalized(month)
    }

    static func monthName(_ date: Date = .now) -> String { capitalized(date.formatted(.dateTime.month(.wide).locale(locale))) }

    /// Wat VoiceOver voorleest voor een regel.
    static func spoken(_ e: CardEvent, card: Card, withTime: Bool) -> String {
        var parts = [title(e, card: card)]
        parts.append(withTime ? whenWithTime(e.date) : when(e.date))
        parts.append(e.amount.map { String(localized: "uitgegeven \(money($0, card: card))") } ?? String(localized: "geen bedrag ingevuld"))
        return parts.joined(separator: ", ")
    }
}

/// Klein, afgerond logo van de winkel in de kleur van de kaart.
struct UseLogoTile: View {
    let card: Card
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 42

    var body: some View {
        let appearance = CardAppearance(card)
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Color(hex: appearance.colorHex))
            .frame(width: size, height: size)
            .overlay {
                if let data = appearance.logoData {
                    StoreLogoMark(data: data, style: appearance.logoStyle, height: size * 0.42, maxWidth: size * 0.8)
                } else {
                    Text(appearance.monogram)
                        .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.onCard(appearance.colorHex))
                        .minimumScaleFactor(0.5)
                        .padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// Eén regel: logo, filiaal (of winkel), wanneer, en rechts het bedrag of de knop Toevoegen.
struct UseRow: View {
    let card: Card
    let event: CardEvent
    var withTime = false
    var onAmount: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            UseLogoTile(card: card)
            VStack(alignment: .leading, spacing: 1) {
                Text(UseFormat.title(event, card: card))
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(withTime ? UseFormat.whenWithTime(event.date) : UseFormat.when(event.date))
                    if event.receiptID != nil {
                        Image(systemName: "doc.text.fill").imageScale(.small).accessibilityLabel(Text("met bonnetje"))
                    }
                    if event.source == "pay" {
                        Image(systemName: "wave.3.right").imageScale(.small).accessibilityLabel(Text("via Opdrachten"))
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            if let amount = event.amount {
                Text(UseFormat.money(amount, card: card))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            } else if let pending = event.pendingAmount {
                // cadeaukaart via Opdrachten: wacht op bevestiging voordat het van het tegoed gaat
                Button(action: onAmount) {
                    Text("Afboeken \(UseFormat.money(pending, card: card))?").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(Brand.coral)
            } else {
                Button(action: onAmount) {
                    Text("Toevoegen").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(Brand.iris)
                .accessibilityLabel(Text("Bedrag toevoegen"))
                .accessibilityHint(Text("Vul in wat je uitgaf bij \(UseFormat.title(event, card: card))"))
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Het paneel onder de knoppen in het kaartdetail (zoals "Laatste transacties" in Apple Wallet): de laatste drie keer.
struct RecentUsesSection: View {
    let card: Card
    var onAll: () -> Void
    var onAmount: (CardEvent) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        let uses = Array(card.uses.prefix(3))
        if !uses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Laatst gebruikt")
                        .font(.title3.weight(.heavy))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    // op een eigen vlak, zodat het ook over de wazige achtergrond (licht en donker) goed leesbaar is
                    Button(action: onAll) {
                        Text("Alles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.irisText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Brand.inkRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Alles van Laatst gebruikt"))
                }
                .padding(.horizontal, 4)
                UsesPanel {
                    ForEach(Array(uses.enumerated()), id: \.element.id) { index, e in
                        UseRow(card: card, event: e) { onAmount(e) }
                            .onTapGesture { onAmount(e) }
                            .swipeToDelete { UseActions.delete(e, from: card, in: context) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityAction { onAmount(e) }
                            .accessibilityAction(named: Text("Verwijder")) { UseActions.delete(e, from: card, in: context) }
                            .accessibilityLabel(Text(UseFormat.spoken(e, card: card, withTime: false)))
                            .accessibilityHint(Text(e.amount == nil ? "Dubbeltik om een bedrag toe te voegen" : "Dubbeltik om het bedrag aan te passen"))
                            .accessibilityAddTraits(.isButton)
                        if index < uses.count - 1 { Divider() }
                    }
                }
            }
        }
    }
}

/// Eigen, niet-doorzichtig vlak (licht: wit, donker: bijna zwart), afgerond als in Wallet.
struct UsesPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension Brand {
    /// Paars voor links en knoppen met tekst: lichter in donker, zodat het goed leesbaar is.
    static let irisText = Color.adaptive(light: "#5A4BEF", dark: "#9C90FF")
}

/// "Alles": grote titel, deze maand in twee tegels, en alle keren per periode. Tik op een regel om het bedrag aan te
/// passen of de regel te verwijderen.
struct RecentUsesView: View {
    @Bindable var card: Card
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var editing: CardEvent?
    @State private var scanning = false
    @State private var openReceipt: Receipt?
    @Query(sort: \Receipt.date, order: .reverse) private var allReceipts: [Receipt]
    private var receipts: [Receipt] { allReceipts.filter { $0.cardID == card.id } }

    private var uses: [CardEvent] { card.uses }
    private var thisMonth: [CardEvent] {
        uses.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }
    private struct UseGroup: Identifiable {
        let title: String
        var events: [CardEvent]
        var id: String { title }
    }

    private var groups: [UseGroup] {
        var out: [UseGroup] = []
        for e in uses {
            let title = UseFormat.group(e.date)
            if out.last?.title == title { out[out.count - 1].events.append(e) } else { out.append(UseGroup(title: title, events: [e])) }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tiles
                    if uses.isEmpty {
                        ContentUnavailableView {
                            Label("Nog niet gebruikt", systemImage: "clock")
                        } description: {
                            Text("Laat je de kaart minstens 5 seconden zien, dan vraagt Pasr bij het sluiten of je hem gebruikte. Zeg je Ja, dan staat het hier, en kun je invullen wat je uitgaf.")
                        }
                        .padding(.top, 20)
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title.uppercased(with: UseFormat.locale))
                                .font(.footnote.weight(.bold))
                                .tracking(0.6)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityLabel(Text(group.title))
                            UsesPanel {
                                ForEach(Array(group.events.enumerated()), id: \.element.id) { index, e in
                                    Button { editing = e } label: {
                                        UseRow(card: card, event: e, withTime: true) { editing = e }
                                    }
                                    .buttonStyle(.plain)
                                    .swipeToDelete { UseActions.delete(e, from: card, in: context) }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityAction(named: Text("Verwijder")) { UseActions.delete(e, from: card, in: context) }
                                    .accessibilityLabel(Text(UseFormat.spoken(e, card: card, withTime: true)))
                                    .accessibilityHint(Text("Dubbeltik om het bedrag aan te passen of de regel te verwijderen"))
                                    .accessibilityAddTraits(.isButton)
                                    if index < group.events.count - 1 { Divider() }
                                }
                            }
                        }
                    }
                    receiptsSection
                    Text("Even kijken telt niet: een moment komt erbij als je na het tonen Ja zegt, of als een aankoop via Opdrachten binnenkomt. Tik op een regel om het bedrag aan te passen of een bonnetje toe te voegen; veeg naar links om te verwijderen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    if card.kind == .voucher {
                        Text("Bij een cadeaukaart wordt een ingevuld bedrag ook van je tegoed afgeboekt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Laatst gebruikt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(card.storeName).font(.headline).accessibilityHidden(true)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Klaar", systemImage: "checkmark") { dismiss() } }
            }
            .sheet(item: $editing) { e in
                UseAmountSheet(card: card, useID: e.id, allowsDelete: true, offersReceipt: true)
            }
            .sheet(isPresented: $scanning) { ReceiptScanFlow(card: card, useID: nil) }
            .sheet(item: $openReceipt) { r in ReceiptDetailView(receipt: r) }
        }
    }

    /// Bonnetjes van deze kaart, nieuwste eerst, en een knop om er een (los) toe te voegen.
    private var receiptsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("BONNETJES")
                    .font(.footnote.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(Text("Bonnetjes"))
                Spacer()
                Button { scanning = true } label: { Label("Bon scannen", systemImage: "doc.viewfinder") }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.irisText)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            if receipts.isEmpty {
                Text("Bewaar de kassabon van een grote aankoop, met een herinnering voordat de garantie afloopt.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                UsesPanel {
                    ForEach(Array(receipts.enumerated()), id: \.element.id) { index, r in
                        Button { openReceipt = r } label: { ReceiptRow(receipt: r) }
                            .buttonStyle(.plain)
                        if index < receipts.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private var tiles: some View {
        let count = thisMonth.count
        let total = thisMonth.compactMap(\.amount).reduce(0, +)
        return HStack(spacing: 8) {
            tile(UseFormat.monthName(), value: String(localized: "\(count)× gebruikt"),
                 spoken: String(localized: "In \(UseFormat.monthName()) \(count) keer gebruikt"))
            tile(String(localized: "Ingevuld"), value: UseFormat.money(total, card: card),
                 spoken: String(localized: "Ingevuld in \(UseFormat.monthName()): \(UseFormat.money(total, card: card))"))
        }
    }

    private func tile(_ label: String, value: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.heavy).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }
}

/// "Wat gaf je uit?" bij één gebruiksmoment: invullen, aanpassen of weghalen; vanuit de lijst ook de regel verwijderen.
struct UseAmountSheet: View {
    @Bindable var card: Card
    let useID: UUID
    var allowsDelete = false
    /// Met de knop "Bonnetje scannen" (of het gekoppelde bonnetje tonen).
    var offersReceipt = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var confirmDelete = false
    @State private var scanning = false
    @State private var showReceipt: Receipt?
    @Query private var receipts: [Receipt]
    @FocusState private var focused: Bool

    private var event: CardEvent? { card.history.first { $0.id == useID } }
    /// "6,48", "1.234,50" of "6.48".
    private var value: Double? {
        var t = text.filter { $0.isNumber || $0 == "," || $0 == "." }
        if t.contains(",") { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        guard let v = Double(t), v >= 0, v < 1_000_000 else { return nil }
        return v
    }
    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let e = event {
                    VStack(spacing: 2) {
                        Text(UseFormat.title(e, card: card)).font(.headline)
                        Text(UseFormat.whenWithTime(e.date))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("€").font(.system(.largeTitle, design: .rounded).weight(.heavy)).foregroundStyle(.secondary)
                    TextField("0,00", text: $text)
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .fixedSize()
                        .accessibilityLabel(Text("Bedrag in euro"))
                }
                if card.kind == .voucher {
                    Text("Wordt afgeboekt van je tegoed (nu \(CardHistoryFormat.money(card.balance ?? 0, card.currencyCode))).")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    Text("Optioneel. Alleen voor jezelf, om bij te houden wat je bij deze winkel uitgeeft.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if event?.amount != nil {
                    Button("Bedrag weghalen", role: .destructive) { save(nil) }
                }
                if offersReceipt {
                    if let rid = event?.receiptID, let r = receipts.first(where: { $0.id == rid }) {
                        Button { showReceipt = r } label: { Label("Bonnetje bekijken", systemImage: "doc.text.fill") }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    } else {
                        Button { scanning = true } label: { Label("Bonnetje scannen", systemImage: "doc.viewfinder") }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            .tint(Brand.iris)
                    }
                }
                Spacer(minLength: 0)
                if allowsDelete {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Regel verwijderen", systemImage: "trash")
                    }
                    .confirmationDialog("Deze regel verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Verwijder", role: .destructive) { delete() }
                    } message: {
                        if card.kind == .voucher, event?.spentID != nil {
                            Text("Het bedrag gaat terug naar je tegoed.")
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Wat gaf je uit?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", systemImage: "checkmark") { save(trimmed.isEmpty ? nil : value) }
                        .disabled(!trimmed.isEmpty && value == nil)
                }
            }
            .onAppear {
                if let a = event?.amount ?? event?.pendingAmount {
                    text = a.formatted(.number.precision(.fractionLength(2)).locale(UseFormat.locale))
                }
                focused = true
            }
            .sheet(isPresented: $scanning) {
                ReceiptScanFlow(card: card, useID: useID) { total in
                    // bedrag van de bon voorvullen als er nog niets staat
                    if trimmed.isEmpty, let total {
                        text = total.formatted(.number.precision(.fractionLength(2)).locale(UseFormat.locale))
                    }
                }
            }
            .sheet(item: $showReceipt) { r in ReceiptDetailView(receipt: r) }
        }
        .presentationDetents([.medium, .large])
    }

    private func save(_ amount: Double?) {
        card.setAmount(amount, forUse: useID)
        finish()
    }

    private func delete() {
        if let e = event { UseActions.delete(e, from: card, in: context) }
        dismiss()
    }

    private func finish() {
        try? context.save()
        let card = card
        if card.kind == .voucher { Task { await WalletPass.refreshIfInWallet(card) } }
        dismiss()
    }
}

/// Een gebruiksmoment verwijderen (vegen of de knop): bij een cadeaukaart gaat een afgeboekt bedrag terug naar het
/// tegoed. Een bonnetje bij het moment blijft bewaard (los bij de kaart).
enum UseActions {
    @MainActor
    static func delete(_ e: CardEvent, from card: Card, in context: ModelContext) {
        withAnimation(.snappy) { card.removeEvent(e) }
        if let rid = e.receiptID,
           let r = try? context.fetch(FetchDescriptor<Receipt>(predicate: #Predicate { $0.id == rid })).first {
            r.useID = nil
        }
        try? context.save()
        if card.kind == .voucher { Task { await WalletPass.refreshIfInWallet(card) } }
    }
}

/// Naar links vegen om te verwijderen, ook buiten een List (zoals in Wallet). Alleen horizontaal: verticaal scrollen
/// blijft gewoon werken.
struct SwipeToDelete: ViewModifier {
    var onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var dragging = false
    private let reveal: CGFloat = 88

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(role: .destructive) {
                    withAnimation(.snappy) { offset = 0 }
                    onDelete()
                } label: {
                    Label("Verwijder", systemImage: "trash.fill")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: max(-offset, 0), height: 44)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            content
                .background(Brand.inkRaised)
                .offset(x: offset)
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.4 || dragging else { return }
                    dragging = true
                    offset = min(0, v.translation.width + (offset <= -reveal && !dragging ? -reveal : 0))
                }
                .onEnded { v in
                    defer { dragging = false }
                    guard dragging else { return }
                    withAnimation(.snappy) {
                        if v.translation.width < -220 { offset = 0; onDelete() }
                        else { offset = v.translation.width < -reveal / 2 ? -reveal : 0 }
                    }
                }
        )
    }
}

extension View {
    func swipeToDelete(_ onDelete: @escaping () -> Void) -> some View { modifier(SwipeToDelete(onDelete: onDelete)) }
}
