import SwiftUI
import MapKit

/// Acties → Tickets: gratis events van de zaak (eigenaar). Lijst met teller, openen voor overzicht en aanmeldingen.
/// De vensters (maken, overzicht) staan in CardsView, buiten de lijst.
struct TicketEventsSection: View {
    let business: Business
    var reload: Int
    let onCreate: () -> Void
    let onOpen: (TicketEvent) -> Void
    @State private var events: [TicketEvent] = []
    @State private var error: String?

    var body: some View {
        Section {
            if events.isEmpty {
                Text("Nog geen events. Maak een gratis event met tickets en QR-code.").foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                Button { onOpen(event) } label: { TicketEventRow(event: event) }
                    .buttonStyle(.plain)
            }
            Button("Event aanmaken", systemImage: "plus") { onCreate() }
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.coral) }
        } header: {
            Text("Tickets")
        } footer: {
            Text("Alleen gratis tickets. Klanten melden zich aan via de link of QR-code en krijgen hun ticket in Pasr en Wallet.")
        }
        .task(id: "\(business.id)-\(reload)") { await load() }
    }

    private func load() async {
        do {
            events = try await TKAPI.events(business: business.id)
            error = nil
        } catch {
            self.error = String(localized: "Events laden mislukt.") + " " + error.localizedDescription
        }
    }
}

struct TicketEventRow: View {
    let event: TicketEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color(hex: event.color ?? "#24346B"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: event.name).font(.headline).lineLimit(1)
                Text(verbatim: TKFormat.eventLine(event.startsAt, event.endsAt)).font(.subheadline).foregroundStyle(.secondary)
                Text(String(format: String(localized: "%lld/%lld aangemeld"), event.registered, event.capacity))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            TKStatusPill(status: event.status)
        }
        .contentShape(Rectangle())
    }
}

// MARK: Event maken of bewerken

struct EventEditorView: View {
    let business: Business
    @State var event: TicketEvent
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var message: String?
    @State private var locating = false
    @State private var saved = false

    private var isNew: Bool { event.id.isEmpty }
    private var valid: Bool {
        !event.name.trimmingCharacters(in: .whitespaces).isEmpty && event.endsAt > event.startsAt && event.capacity > 0
            && event.ticketTypes.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                basics
                timing
                place
                spots
                types
                branding
                Section {
                    Text("Bij aanmelden vragen we voornaam, achternaam, e-mailadres en geboortedatum (verplicht). Op het ticket staat alleen de naam; de QR-code bevat geen persoonsgegevens.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Section { Text(message).foregroundStyle(Theme.coral) } }
                actions
            }
            .navigationTitle(isNew ? Text("Nieuw event") : Text("Event bewerken"))
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Opslaan") { Task { await save(event.isCancelled ? "cancelled" : event.status) } }.disabled(!valid)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
    }

    private var basics: some View {
        Section("Event") {
            TextField("Naam (bijv. Winterborrel)", text: $event.name)
            TextField("Omschrijving", text: $event.description, axis: .vertical).lineLimit(3...8)
        }
    }

    private var timing: some View {
        Section("Datum en tijd") {
            DatePicker("Begint", selection: $event.startsAt, displayedComponents: [.date, .hourAndMinute])
                .onChange(of: event.startsAt) { old, new in
                    // eindtijd schuift mee
                    if event.endsAt <= new { event.endsAt = new.addingTimeInterval(max(3600, event.endsAt.timeIntervalSince(old))) }
                }
            DatePicker("Eindigt", selection: $event.endsAt, in: event.startsAt..., displayedComponents: [.date, .hourAndMinute])
            Toggle("Deuren open", isOn: Binding(get: { event.doorsAt != nil },
                                                set: { event.doorsAt = $0 ? event.startsAt.addingTimeInterval(-900) : nil }))
            if event.doorsAt != nil {
                DatePicker("Deuren open om", selection: Binding(get: { event.doorsAt ?? event.startsAt }, set: { event.doorsAt = $0 }),
                           in: ...event.startsAt, displayedComponents: [.date, .hourAndMinute])
            }
        }
    }

    private var place: some View {
        Section {
            HStack {
                TextField("Adres", text: $event.address)
                    .textContentType(.fullStreetAddress)
                if locating { ProgressView() } else {
                    Button("Zoek", systemImage: "magnifyingglass") { Task { await locate() } }
                        .labelStyle(.iconOnly)
                        .disabled(event.address.trimmingCharacters(in: .whitespaces).count < 4)
                }
            }
            if let lat = event.lat, let lng = event.lng {
                EventMap(lat: lat, lng: lng)
                    .frame(height: 150)
                    .listRowInsets(EdgeInsets())
            }
        } header: {
            Text("Adres")
        } footer: {
            Text("Met Zoek komt het event op de kaart; klanten krijgen dan een route.")
        }
    }

    private var spots: some View {
        Section("Plekken en aanmelden") {
            Stepper(value: $event.capacity, in: 1...100_000, step: event.capacity >= 100 ? 10 : 1) {
                LabeledContent("Aantal plekken") { Text(verbatim: "\(event.capacity)").monospacedDigit() }
            }
            Stepper(value: $event.maxPerPerson, in: 1...20) {
                LabeledContent("Max. per persoon") { Text(verbatim: "\(event.maxPerPerson)").monospacedDigit() }
            }
            Toggle("Aanmelden tot een datum", isOn: Binding(get: { event.signupUntil != nil },
                                                           set: { event.signupUntil = $0 ? event.startsAt.addingTimeInterval(-4 * 3600) : nil }))
            if event.signupUntil != nil {
                DatePicker("Aanmelden tot", selection: Binding(get: { event.signupUntil ?? event.startsAt }, set: { event.signupUntil = $0 }),
                           in: ...event.endsAt, displayedComponents: [.date, .hourAndMinute])
            }
            Toggle(isOn: $event.waitlist) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wachtlijst")
                    Text("Bij vol: aanmelden op de wachtlijst, automatisch doorschuiven").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var types: some View {
        Section {
            ForEach($event.ticketTypes) { $type in
                TicketTypeRow(type: $type)
                    .macContextMenu {
                        if event.ticketTypes.count > 1 {
                            Button("Soort verwijderen", systemImage: "trash", role: .destructive) {
                                event.ticketTypes.removeAll { $0.id == type.id }
                            }
                        }
                    }
            }
            .onDelete { idx in
                if event.ticketTypes.count > 1 { event.ticketTypes.remove(atOffsets: idx) }
            }
            Button("Soort toevoegen", systemImage: "plus") {
                event.ticketTypes.append(TicketType())
            }
        } header: {
            Text("Ticketsoorten (allemaal gratis)")
        } footer: {
            Text("Minstens één soort. Laat plekken leeg om de plekken van het event te delen.")
        }
    }

    private var branding: some View {
        Section {
            TKColorRow(color: $event.color)
            TextField("Header-afbeelding (link, optioneel)", text: Binding(get: { event.headerURL ?? "" }, set: { event.headerURL = $0 }))
                .keyboard(.url)
                .capitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Branding")
        } footer: {
            Text("Standaard het logo en de kleur van je zaak.")
        }
    }

    @ViewBuilder private var actions: some View {
        Section {
            if !event.isPublished && !event.isCancelled {
                Button { Task { await save("published") } } label: {
                    Label("Online zetten", systemImage: "checkmark.seal")
                }
                .disabled(!valid || busy || !business.isApproved)
                Button { Task { await save("draft") } } label: {
                    Label("Concept bewaren", systemImage: "square.and.arrow.down")
                }
                .disabled(!valid || busy)
            } else if event.isPublished {
                Button { Task { await save("draft") } } label: {
                    Label("Offline halen (concept)", systemImage: "eye.slash")
                }
                .disabled(!valid || busy)
            }
        } footer: {
            if !business.isApproved {
                Text("Je zaak is nog niet goedgekeurd. Online zetten kan pas daarna.")
            }
        }
    }

    private func locate() async {
        locating = true
        defer { locating = false }
        if let c = await Geocoder.locate(event.address) {
            withAnimation { event.lat = c.latitude; event.lng = c.longitude }
        } else {
            message = String(localized: "Dit adres is niet gevonden. Controleer het en probeer opnieuw.")
        }
    }

    private func save(_ status: String) async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await TKAPI.saveEvent(event, business: business.id, status: status)
            saved.toggle()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct TicketTypeRow: View {
    @Binding var type: TicketType

    var body: some View {
        HStack {
            TextField("Naam (bijv. Toegang)", text: $type.name)
            TextField("Plekken", value: $type.capacity, format: .number)
                .keyboard(.number)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }
}

struct EventMap: View {
    let lat: Double
    let lng: Double

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700))) {
            Marker("", coordinate: coordinate).tint(Theme.coral)
        }
        .allowsHitTesting(false)
        .id("\(lat),\(lng)")
    }
}

// MARK: Overzicht van een event

struct EventDetailView: View {
    let business: Business
    @State var event: TicketEvent
    @Environment(\.dismiss) private var dismiss
    @State private var registrations: [EventRegistration] = []
    @State private var search = ""
    @State private var error: String?
    @State private var editing = false
    @State private var sharing = false
    @State private var askCancel = false
    @State private var cancelMessage = ""
    @State private var busy = false
    @State private var csv: URL?

    private var filtered: [EventRegistration] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return registrations }
        return registrations.filter { $0.fullName.lowercased().contains(q) || $0.email.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { EventStatsView(event: event).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                buttons
                registrationList
                if let error { Section { Text(error).foregroundStyle(Theme.coral) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .searchable(text: $search, prompt: Text("Zoek op naam of e-mail"))
            .navigationTitle(Text(verbatim: event.name))
            .inlineTitle()
            .refreshable { await load() }
            .macRefreshButton { await load() }
            .task { await load() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if !event.isCancelled {
                        Button("Bewerken", systemImage: "pencil") { editing = true }
                    }
                }
            }
            .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) {
                EventEditorView(business: business, event: event).macSheetFrame()
            }
            .sheet(isPresented: $sharing) {
                TKShareView(title: event.name, url: event.addURL,
                            intro: "Klanten scannen deze code of openen de link en melden zich gratis aan. Hun ticket komt in Pasr en Wallet.",
                            badgeIntro: "Klanten melden zich met één tik aan voor je event in Pasr. Zonder Pasr opent pasr.nl.")
                    .macSheetFrame()
            }
            .alert("Event annuleren?", isPresented: $askCancel) {
                TextField("Bericht aan de aanmeldingen", text: $cancelMessage)
                Button("Event annuleren", role: .destructive) { Task { await cancelEvent() } }
                Button("Terug", role: .cancel) {}
            } message: {
                Text("Iedereen die zich heeft aangemeld krijgt een mail en melding met je bericht. Dit kan niet ongedaan worden gemaakt.")
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        Section {
            if event.isPublished {
                Button("Delen: link, QR en knop voor je website", systemImage: "qrcode") { sharing = true }
            }
            if let csv {
                ShareLink(item: csv) { Label("Exporteer CSV", systemImage: "square.and.arrow.up") }
            }
            if !event.isCancelled && !event.isPast {
                Button("Event annuleren", systemImage: "xmark.octagon", role: .destructive) { askCancel = true }
                    .disabled(busy)
            }
        } footer: {
            Text("Scannen aan de deur gaat via Scannen. Kies daar dit event om alleen deze tickets toe te laten.")
        }
    }

    private var registrationList: some View {
        Section {
            if registrations.isEmpty {
                Text("Nog geen aanmeldingen").foregroundStyle(.secondary)
            }
            ForEach(filtered) { r in
                RegistrationRow(registration: r)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let id = r.registrationID, r.status != "cancelled" {
                            Button("Afmelden", role: .destructive) { Task { await cancelRegistration(id) } }
                        }
                    }
                    .macContextMenu {
                        if let id = r.registrationID, r.status != "cancelled" {
                            Button("Afmelden", systemImage: "person.badge.minus", role: .destructive) {
                                Task { await cancelRegistration(id) }
                            }
                        }
                    }
            }
        } header: {
            Text("Aanmeldingen")
        } footer: {
            AppPlatform.isMac
                ? Text("Geboortedatum en e-mail zie alleen jij; ze staan niet op het ticket en niet in de QR-code. Klik met de rechtermuisknop op een aanmelding om iemand af te melden.")
                : Text("Geboortedatum en e-mail zie alleen jij; ze staan niet op het ticket en niet in de QR-code. Veeg naar links om iemand af te melden.")
        }
    }

    private func load() async {
        do {
            if let fresh = try await TKAPI.events(business: business.id).first(where: { $0.id == event.id }) { event = fresh }
            registrations = try await TKAPI.registrations(business: business.id, event: event.id)
            csv = EventCSV.write(event: event, rows: registrations)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func cancelRegistration(_ id: String) async {
        do {
            try await TKAPI.cancelRegistration(business: business.id, registration: id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func cancelEvent() async {
        busy = true
        defer { busy = false }
        do {
            try await TKAPI.cancelEvent(business: business.id, event: event.id, message: cancelMessage)
            cancelMessage = ""
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct EventStatsView: View {
    let event: TicketEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: TKFormat.eventLine(event.startsAt, event.endsAt)).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                TKStatusPill(status: event.status)
            }
            if !event.address.isEmpty {
                Label { Text(verbatim: event.address) } icon: { Image(systemName: "mappin.and.ellipse") }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                tile("Aangemeld", "\(event.registered) / \(event.capacity)", Theme.iris)
                tile("Binnen", "\(event.checkedIn)", Theme.mint)
                tile("Wachtlijst", "\(event.waiting)", Theme.amber)
            }
            ProgressView(value: Double(min(event.registered, max(1, event.capacity))), total: Double(max(1, event.capacity)))
                .tint(Theme.iris)
            Text(String(format: String(localized: "%lld plekken vrij"), event.spotsLeft))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func tile(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: value).font(.title3.weight(.heavy)).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct RegistrationRow: View {
    let registration: EventRegistration

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(verbatim: registration.fullName).font(.body.weight(.semibold))
                Spacer()
                status
            }
            Text(verbatim: registration.email).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack(spacing: 8) {
                if let birth = registration.birthDate {
                    Text(verbatim: birth.formatted(date: .numeric, time: .omitted))
                }
                if !registration.ticketType.isEmpty { Text(verbatim: "· " + registration.ticketType) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        switch registration.status {
        case "checked_in":
            pill(registration.checkedInAt.map { String(format: String(localized: "Binnen %@"), $0.formatted(date: .omitted, time: .shortened)) }
                 ?? String(localized: "Binnen"), Theme.mint)
        case "waitlist": pill(String(localized: "Wachtlijst"), Theme.amber)
        case "cancelled": pill(String(localized: "Afgemeld"), Theme.coral)
        default: pill(String(localized: "Aangemeld"), Theme.iris)
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(verbatim: text).font(.caption.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Aanmeldingen als CSV (voor de eigenaar; bevat persoonsgegevens, dus alleen lokaal en via Delen).
enum EventCSV {
    static func write(event: TicketEvent, rows: [EventRegistration]) -> URL? {
        guard !rows.isEmpty else { return nil }
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["voornaam;achternaam;email;geboortedatum;ticketsoort;status;aangemeld;binnen"]
        for r in rows {
            lines.append([r.firstName, r.lastName, r.email, r.birthDate.map(TKFormat.day) ?? "", r.ticketType, r.status,
                          r.createdAt.map(TKFormat.timestamp) ?? "", r.checkedInAt.map(TKFormat.timestamp) ?? ""].map(esc).joined(separator: ";"))
        }
        let safe = event.name.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Aanmeldingen \(safe.isEmpty ? "event" : safe).csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch { return nil }
    }
}
