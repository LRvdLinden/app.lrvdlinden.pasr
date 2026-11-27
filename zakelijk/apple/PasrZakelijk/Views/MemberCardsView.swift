import SwiftUI
import UIKit
import PhotosUI

/// Acties → Klantenkaarten: eigen klantenkaart met barcode (eigenaar). Scannen gaat via Scannen.
/// De vensters (maken, bewerken, delen) staan in CardsView, buiten de lijst.
struct MemberCardsSection: View {
    let business: Business
    var reload: Int
    let onCreate: () -> Void
    let onEdit: (MemberCard) -> Void
    let onShare: (MemberCard) -> Void
    @State private var cards: [MemberCard] = []
    @State private var error: String?

    var body: some View {
        Section {
            if cards.isEmpty {
                Text("Nog geen klantenkaart. Maak er een met je eigen logo, kleur en barcode.").foregroundStyle(.secondary)
            }
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 10) {
                    Button { onEdit(card) } label: { MemberCardRow(card: card) }
                        .buttonStyle(.plain)
                    if card.isPublished {
                        Button("Delen: link, QR en knop voor je website", systemImage: "qrcode") { onShare(card) }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.borderless)
                    }
                }
            }
            Button("Klantenkaart aanmaken", systemImage: "plus") { onCreate() }
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.coral) }
        } header: {
            Text("Klantenkaarten")
        } footer: {
            Text("Pasr maakt de kaartnummers zelf (QR, Code 128 of EAN-13). Scannen gaat met Pasr Zakelijk.")
        }
        .task(id: "\(business.id)-\(reload)") { await load() }
    }

    /// Delen: link /add/m/<id>, QR en de knop voor de website.
    static func share(_ card: MemberCard) -> some View {
        TKShareView(title: card.name, url: card.addURL,
                    intro: "Klanten scannen deze code of openen de link en zetten je klantenkaart in Pasr en Wallet.",
                    badgeIntro: "Klanten zetten je klantenkaart met één tik in Pasr. Zonder Pasr opent pasr.nl met de downloadknoppen.")
    }

    private func load() async {
        do {
            cards = try await TKAPI.memberCards(business: business.id).filter { $0.status != "archived" }
            error = nil
        } catch {
            self.error = String(localized: "Klantenkaarten laden mislukt.") + " " + error.localizedDescription
        }
    }
}

struct MemberCardRow: View {
    let card: MemberCard

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.barcodeType == "qr" ? "qrcode" : "barcode")
                .font(.headline)
                .foregroundStyle(Color.onCard(card.color))
                .frame(width: 40, height: 40)
                .background(Color(hex: card.color), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: card.name).font(.headline).lineLimit(1)
                Text(String(format: String(localized: "%lld leden"), card.members)).font(.subheadline).foregroundStyle(.secondary)
                if let d = card.discountNow {
                    Text(String(format: String(localized: "Nu %@%% korting"), TKFormat.percent(d.percent)))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.mint)
                } else if let n = card.nextDiscount, let at = n.startsAt {
                    Text(String(format: String(localized: "Volgende korting: %@"), TKFormat.soon(at)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            TKStatusPill(status: card.status)
        }
        .contentShape(Rectangle())
    }
}

// MARK: Klantenkaart maken of bewerken

struct MemberCardEditorView: View {
    let business: Business
    @State var card: MemberCard
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var logoChanged = false
    @State private var busy = false
    @State private var message: String?
    @State private var saved = false
    @State private var period: DiscountPeriod?
    @State private var timeline = false
    @State private var confirmArchive = false

    private var isNew: Bool { card.id.isEmpty }
    private var goalsChosen: Bool {
        card.goals.membership || card.goals.savingEnabled || card.goals.fixedEnabled || !card.goals.periods.isEmpty
    }
    private var valid: Bool {
        !card.name.trimmingCharacters(in: .whitespaces).isEmpty && goalsChosen
            && (!card.goals.savingEnabled || !card.goals.savingReward.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MemberCardPreview(card: card, business: business.name, memberName: "Anna de Vries")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                basics
                barcode
                MemberGoalsSection(goals: $card.goals)
                periods
                if let message { Section { Text(message).foregroundStyle(Theme.coral) } }
                actions
            }
            .navigationTitle(isNew ? Text("Nieuwe klantenkaart") : Text("Klantenkaart bewerken"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Opslaan") { Task { await save(card.status) } }.disabled(!valid)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                       let encoded = LogoImage.encode(image) {
                        card.logo = encoded
                        logoChanged = true
                    } else {
                        message = String(localized: "Dit bestand is geen afbeelding.")
                    }
                }
            }
            .sheet(item: $period) { p in
                PeriodEditorView(period: p) { updated in
                    if let i = card.goals.periods.firstIndex(where: { $0.id == updated.id }) { card.goals.periods[i] = updated }
                    else { card.goals.periods.append(updated) }
                } onDelete: {
                    card.goals.periods.removeAll { $0.id == p.id }
                }
            }
            .confirmationDialog("Klantenkaart archiveren?", isPresented: $confirmArchive, titleVisibility: .visible) {
                Button("Archiveren", role: .destructive) { Task { await save("archived") } }
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text("Klanten kunnen de kaart dan niet meer toevoegen en scannen werkt niet meer.")
            }
        }
    }

    private var basics: some View {
        Section("Kaart") {
            TextField("Naam (bijv. Korenschoof Klantenkaart)", text: $card.name)
            TKColorRow(color: Binding(get: { card.color }, set: { card.color = $0 ?? card.color }), allowDefault: false)
            PhotosPicker(selection: $photo, matching: .images) {
                Label(card.logo == nil ? "Logo kiezen" : "Ander logo kiezen", systemImage: "photo")
            }
            if card.logo != nil {
                Button("Logo weghalen", role: .destructive) { card.logo = nil; logoChanged = true }
            }
        }
    }

    private var barcode: some View {
        Section {
            Picker("Soort barcode", selection: $card.barcodeType) {
                Text("QR-code").tag("qr")
                Text("Code 128").tag("code128")
                Text("EAN-13").tag("ean13")
            }
            .pickerStyle(.segmented)
            if card.barcodeType != "ean13" {
                TextField("Voorvoegsel kaartnummer (bijv. KS-)", text: $card.prefix)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: card.prefix) { _, v in if v.count > 8 { card.prefix = String(v.prefix(8)) } }
            }
            LabeledContent("Nummering") { Text(verbatim: card.sampleNumber).font(.body.monospaced()).foregroundStyle(.secondary) }
        } header: {
            Text("Barcode")
        } footer: {
            Text("Pasr maakt de nummers zelf. Scannen gaat met Pasr Zakelijk; koppelen met je eigen kassa komt later.")
        }
    }

    private var periods: some View {
        Section {
            Picker("Weergave", selection: $timeline) {
                Text("Lijst").tag(false)
                Text("Tijdlijn").tag(true)
            }
            .pickerStyle(.segmented)
            if timeline {
                PeriodTimeline(periods: card.goals.periods)
            } else {
                if card.goals.periods.isEmpty {
                    Text("Nog geen kortingsperiodes").foregroundStyle(.secondary)
                }
                ForEach(card.goals.periods) { p in
                    Button { period = p } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: p.label.isEmpty ? String(format: String(localized: "%@%% korting"), TKFormat.percent(p.percent)) : p.label)
                                .font(.body.weight(.semibold))
                            Text(verbatim: p.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { card.goals.periods.remove(atOffsets: $0) }
            }
            Button("Periode toevoegen", systemImage: "plus") { period = DiscountPeriod() }
        } header: {
            Text("Korting in een periode")
        } footer: {
            Text("Van–tot, eventueel alleen op bepaalde dagen of uren. Plan meerdere periodes vooruit.")
        }
    }

    @ViewBuilder private var actions: some View {
        Section {
            if card.isPublished {
                Button { Task { await save("draft") } } label: { Label("Offline halen (concept)", systemImage: "eye.slash") }
                    .disabled(!valid || busy)
            } else {
                Button { Task { await save("published") } } label: { Label("Online zetten", systemImage: "checkmark.seal") }
                    .disabled(!valid || busy || !business.isApproved)
                Button { Task { await save("draft") } } label: { Label("Concept bewaren", systemImage: "square.and.arrow.down") }
                    .disabled(!valid || busy)
            }
            if !isNew {
                Button("Archiveren", systemImage: "archivebox", role: .destructive) { confirmArchive = true }
            }
        } footer: {
            if !goalsChosen { Text("Kies minstens één doel voor de kaart.") }
        }
    }

    private func save(_ status: String) async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await TKAPI.saveMemberCard(card, business: business.id, status: status, logoChanged: logoChanged)
            saved.toggle()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

/// De vier doelen: lidmaatschap, sparen, vaste korting (periodes staan apart).
struct MemberGoalsSection: View {
    @Binding var goals: MemberGoals

    var body: some View {
        Section {
            Toggle(isOn: $goals.membership) {
                goalLabel("Lidmaatschap of herkenning", "De klant laat zijn kaart zien; jij ziet wie het is.", "person.text.rectangle")
            }
            Toggle(isOn: $goals.savingEnabled) {
                goalLabel("Sparen voor een beloning", "Elke scan telt als bezoek of punten.", "star")
            }
            if goals.savingEnabled { saving }
            Toggle(isOn: $goals.fixedEnabled) {
                goalLabel("Vaste korting", "Altijd hetzelfde percentage voor leden.", "percent")
            }
            if goals.fixedEnabled {
                Stepper(value: $goals.fixedPercent, in: 1...100, step: 1) {
                    LabeledContent("Korting") { Text(verbatim: TKFormat.percent(goals.fixedPercent) + "%").monospacedDigit() }
                }
            }
        } header: {
            Text("Doel van de kaart · kies er één of meer")
        }
    }

    @ViewBuilder private var saving: some View {
        Picker("Per scan", selection: $goals.savingUnit) {
            Text("Bezoeken").tag("visits")
            Text("Punten").tag("points")
        }
        .pickerStyle(.segmented)
        Stepper(value: $goals.savingTarget, in: 2...10_000, step: goals.savingTarget >= 50 ? 10 : 1) {
            LabeledContent {
                Text(verbatim: "\(goals.savingTarget)").monospacedDigit()
            } label: {
                Text(goals.savingUnit == "points" ? "Beloning na (punten)" : "Beloning na (bezoeken)")
            }
        }
        TextField("Beloning (bijv. gratis gebakje naar keuze)", text: $goals.savingReward)
    }

    private func goalLabel(_ title: LocalizedStringKey, _ text: LocalizedStringKey, _ icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: icon).foregroundStyle(Theme.iris) }
    }
}

// MARK: Kortingsperiode

struct PeriodEditorView: View {
    @State var period: DiscountPeriod
    let onSave: (DiscountPeriod) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Korting") {
                    TextField("Label (bijv. happy hour)", text: $period.label)
                    Stepper(value: $period.percent, in: 1...100, step: 1) {
                        LabeledContent("Percentage") { Text(verbatim: TKFormat.percent(period.percent) + "%").monospacedDigit() }
                    }
                }
                Section("Periode") {
                    DatePicker("Van", selection: $period.startsOn, displayedComponents: .date)
                    DatePicker("Tot en met", selection: $period.endsOn, in: period.startsOn..., displayedComponents: .date)
                }
                weekdays
                hours
                Section {
                    Button("Periode verwijderen", role: .destructive) { onDelete(); dismiss() }
                }
            }
            .navigationTitle(Text("Kortingsperiode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") {
                        if period.endsOn < period.startsOn { period.endsOn = period.startsOn }
                        onSave(period)
                        dismiss()
                    }
                }
            }
        }
    }

    private var weekdays: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let on = period.weekdays.contains(day)
                    Button {
                        if on { period.weekdays.remove(day) } else { period.weekdays.insert(day) }
                    } label: {
                        Text(verbatim: TKWeekday.short(day))
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(on ? .white : .primary)
                            .background(on ? Theme.iris : Theme.card2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Weekdagen")
        } footer: {
            Text("Niets gekozen = elke dag.")
        }
    }

    private var hours: some View {
        Section("Tijden") {
            Toggle("Alleen tussen bepaalde tijden", isOn: Binding(
                get: { period.fromTime != nil },
                set: {
                    period.fromTime = $0 ? TKFormat.parseTime("17:00") : nil
                    period.toTime = $0 ? TKFormat.parseTime("19:00") : nil
                }))
            if period.fromTime != nil {
                DatePicker("Van", selection: Binding(get: { period.fromTime ?? .now }, set: { period.fromTime = $0 }), displayedComponents: .hourAndMinute)
                DatePicker("Tot", selection: Binding(get: { period.toTime ?? .now }, set: { period.toTime = $0 }), displayedComponents: .hourAndMinute)
            }
        }
    }
}

/// Tijdlijn van één maand met de kortingsperiodes als balken.
struct PeriodTimeline: View {
    let periods: [DiscountPeriod]
    @State private var month = TKFormat.calendar.date(from: TKFormat.calendar.dateComponents([.year, .month], from: .now)) ?? .now

    private var days: Int { TKFormat.calendar.range(of: .day, in: .month, for: month)?.count ?? 30 }
    private var monthEnd: Date { TKFormat.calendar.date(byAdding: DateComponents(day: days - 1), to: month) ?? month }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(Text("Vorige maand"))
                Spacer()
                Text(verbatim: month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel(Text("Volgende maand"))
            }
            .buttonStyle(.borderless)
            let visible = periods.filter { $0.endsOn >= month && $0.startsOn <= monthEnd }
            if visible.isEmpty {
                Text("Geen korting in deze maand").font(.subheadline).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { i, p in
                        bar(p, index: i, width: geo.size.width)
                    }
                }
            }
            .frame(height: CGFloat(max(1, visible.count)) * 30)
        }
        .padding(.vertical, 4)
    }

    private func bar(_ p: DiscountPeriod, index: Int, width: CGFloat) -> some View {
        let c = TKFormat.calendar
        let start = max(p.startsOn, month)
        let end = min(p.endsOn, monthEnd)
        let first = (c.dateComponents([.day], from: month, to: start).day ?? 0)
        let last = (c.dateComponents([.day], from: month, to: end).day ?? 0)
        let unit = width / CGFloat(days)
        let colors = [Theme.iris, Color(hex: "#0F6E6E"), Theme.coral, Theme.amber]
        let text = (p.label.isEmpty ? "" : p.label + " · ") + TKFormat.percent(p.percent) + "%"
        return Text(verbatim: text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(width: max(unit, CGFloat(last - first + 1) * unit), height: 24, alignment: .leading)
            .background(colors[index % colors.count].opacity(p.weekdays.isEmpty && p.fromTime == nil ? 1 : 0.7),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .offset(x: CGFloat(first) * unit)
    }

    private func shift(_ months: Int) {
        month = TKFormat.calendar.date(byAdding: .month, value: months, to: month) ?? month
    }
}
