import SwiftUI
import SwiftData

// MARK: Gratis tickets van een zaak: aanmelden (pasr.nl/add/e/<event>), ticket koppelen (pasr.nl/add/t/<ticket>?c=<code>)
// en wat er onder een ticket in de stapel staat. Zie BusinessPasses voor de server-kant.

/// Kop van een event in de kleur van het event: logo en naam van de zaak, naam, datum/tijd en adres. Met een
/// headerafbeelding (header_url) erachter, als die er is.
struct EventHeaderCard: View {
    let event: BusinessPasses.EventInfo
    @State private var logo: Data?

    private var ink: Color { Color.onCard(event.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let logo {
                    StoreLogoMark(data: logo, style: nil, height: 28, maxWidth: 90, alignment: .leading)
                }
                Text(event.business ?? "")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("GRATIS TICKET")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .opacity(0.8)
            }
            Text(event.name)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let when = event.whenText {
                Label(when, systemImage: "calendar").font(.subheadline.weight(.semibold))
            }
            if let doors = event.doors {
                Label("Deuren open \(doors.formatted(date: .omitted, time: .shortened))", systemImage: "door.left.hand.open")
                    .font(.subheadline)
            }
            if let address = event.address {
                Label(address, systemImage: "mappin.and.ellipse").font(.subheadline).lineLimit(2)
            }
        }
        .foregroundStyle(ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color(hex: event.color)
                if let header = event.header {
                    AsyncImage(url: header) { image in
                        image.resizable().scaledToFill().overlay(Color(hex: event.color).opacity(0.62))
                    } placeholder: { Color.clear }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .task { logo = await BusinessCards.logoData(event.logo) }
        .accessibilityElement(children: .combine)
    }
}

/// Aanmelden voor een gratis event: voornaam, achternaam, e-mailadres, geboortedatum (alle verplicht), ticketsoort en
/// aantal. Ingelogd komen de tickets meteen in Pasr; bij een vol event met wachtlijst kom je op de wachtlijst.
struct EventSignupSheet: View {
    let eventID: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]

    enum Phase: Equatable { case loading, ready, missing(String), done(waitlist: Bool) }

    @State private var phase: Phase = .loading
    @State private var event: BusinessPasses.EventInfo?
    @State private var form = EventSignupForm()
    @State private var busy = false
    @State private var error: String?
    @State private var addedTicket: String?

    private var signedIn: Bool { AccountService.shared.isSignedIn }
    private var myTickets: [Card] { cards.filter { $0.details.isEventTicket && $0.details.eventId == eventID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    switch phase {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                    case .missing(let message):
                        ContentUnavailableView(message, systemImage: "exclamationmark.triangle",
                                               description: Text("Vraag de organisator om een nieuwe link."))
                    case .ready:
                        if let event { readyView(event) }
                    case .done(let waitlist):
                        if let event { EventSignupDone(event: event, waitlist: waitlist, count: form.count) { openInPasr() } }
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle(isDone ? Text("Toegevoegd") : Text("Aanmelden"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isDone ? "Klaar" : "Annuleer", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var isDone: Bool { if case .done = phase { true } else { false } }

    @ViewBuilder private func readyView(_ event: BusinessPasses.EventInfo) -> some View {
        EventHeaderCard(event: event)
        if let description = event.description {
            Text(description).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        if !myTickets.isEmpty {
            Label(myTickets.count == 1 ? "Je hebt al een ticket voor dit event." : "Je hebt al \(myTickets.count) tickets voor dit event.",
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.mint)
            Button("Bekijk in Pasr") { openInPasr() }
        }
        if event.isCancelled {
            notice("Dit event is geannuleerd.", symbol: "xmark.octagon.fill")
        } else if !event.signupOpen && !(event.isFull && event.waitlist) {
            notice("Aanmelden is gesloten.", symbol: "lock.fill")
        } else if !signedIn {
            notice("Log eerst in met je Pasr-account (Instellingen › Account). Je tickets komen dan meteen in je Pasr.",
                   symbol: "person.crop.circle.badge.exclamationmark")
        } else {
            EventSignupFormView(event: event, form: $form)
            if event.isFull && event.waitlist {
                Label("Het event is vol: je komt op de wachtlijst. Komt er een plek vrij, dan krijg je een melding.",
                      systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center)
            }
            Button { Task { await submit(event) } } label: {
                HStack {
                    if busy { ProgressView() }
                    Text(event.isFull && event.waitlist ? "Op de wachtlijst" : "Gratis aanmelden").bold()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .pasrGlassButton(prominent: true)
            .tint(Color(hex: event.color))
            .disabled(busy || !form.isValid)
            Text("Je gegevens gaan alleen naar \(event.business ?? "de organisator") voor dit event. Op het ticket staat alleen je naam; je geboortedatum staat nooit op het ticket of in de QR-code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func notice(_ text: LocalizedStringKey, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func load() async {
        do {
            let info = try await BusinessPasses.event(id: eventID)
            event = info
            form.prefill(maxCount: info.maxPerPerson, types: info.types)
            phase = .ready
        } catch {
            phase = .missing(error.localizedDescription)
        }
    }

    private func submit(_ event: BusinessPasses.EventInfo) async {
        guard let birth = form.birthDate else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let result = try await BusinessPasses.register(event: event.id, firstName: form.firstName, lastName: form.lastName,
                                                           email: form.email, birthDate: birth, ticketType: form.ticketType,
                                                           count: form.count, in: context)
            form.remember()
            addedTicket = result.ticketIDs.first
            withAnimation { phase = .done(waitlist: result.waitlist) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openInPasr() {
        let card = BusinessPasses.ticketCard(event: eventID, ticket: addedTicket, in: cards)
        dismiss()
        if let id = card?.id { NotificationRouter.pendingCardID = id }
    }
}

/// De invoer van het aanmeldformulier, met de laatst gebruikte naam en geboortedatum (alleen op dit toestel).
struct EventSignupForm: Equatable {
    var firstName = ""
    var lastName = ""
    var email = ""
    var birthDate: Date?
    var ticketType: String?
    var count = 1
    var maxCount = 4

    private static let lastNameKey = "pasr.event.lastName"
    private static let birthKey = "pasr.event.birthDate"

    @MainActor
    mutating func prefill(maxCount: Int, types: [BusinessPasses.EventInfo.TicketType]) {
        let session = AccountService.shared.session
        if firstName.isEmpty { firstName = session?.firstName ?? "" }
        if email.isEmpty { email = session?.email ?? "" }
        if lastName.isEmpty { lastName = UserDefaults.standard.string(forKey: Self.lastNameKey) ?? "" }
        if birthDate == nil, UserDefaults.standard.object(forKey: Self.birthKey) != nil {
            birthDate = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.birthKey))
        }
        self.maxCount = max(1, maxCount)
        ticketType = ticketType ?? (types.first { ($0.available ?? 1) > 0 } ?? types.first)?.id
    }

    func remember() {
        UserDefaults.standard.set(lastName.trimmingCharacters(in: .whitespaces), forKey: Self.lastNameKey)
        if let birthDate { UserDefaults.standard.set(birthDate.timeIntervalSince1970, forKey: Self.birthKey) }
    }

    var emailValid: Bool {
        email.trimmingCharacters(in: .whitespaces).range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$", options: .regularExpression) != nil
    }

    var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && emailValid && birthDate.map { $0 < .now } == true && (1...maxCount).contains(count)
    }
}

/// Voornaam, achternaam, e-mailadres, geboortedatum, ticketsoort en aantal.
struct EventSignupFormView: View {
    let event: BusinessPasses.EventInfo
    @Binding var form: EventSignupForm

    private var birthRange: ClosedRange<Date> {
        (Calendar.current.date(byAdding: .year, value: -110, to: .now) ?? .distantPast)...Date.now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                field("Voornaam") {
                    TextField("Voornaam", text: $form.firstName).textContentType(.givenName)
                }
                field("Achternaam") {
                    TextField("Achternaam", text: $form.lastName).textContentType(.familyName)
                }
            }
            field("E-mailadres") {
                TextField("naam@voorbeeld.nl", text: $form.email)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }
            field("Geboortedatum") {
                if let birth = form.birthDate {
                    DatePicker("Geboortedatum", selection: Binding(get: { birth }, set: { form.birthDate = $0 }),
                               in: birthRange, displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "nl_NL"))
                } else {
                    Button("Kies je geboortedatum") {
                        form.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)
                    }
                }
            }
            if event.types.count > 1 {
                field("Ticketsoort") {
                    Picker("Ticketsoort", selection: Binding(get: { form.ticketType ?? "" }, set: { form.ticketType = $0 })) {
                        ForEach(event.types) { type in
                            Text(typeTitle(type)).tag(type.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            field("Aantal tickets") {
                Stepper(value: $form.count, in: 1...form.maxCount) {
                    Text("\(form.count) × \(event.types.first { $0.id == form.ticketType }?.name ?? String(localized: "Toegang"))")
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func typeTitle(_ type: BusinessPasses.EventInfo.TicketType) -> String {
        guard let available = type.available else { return type.name }
        return available <= 0 ? String(localized: "\(type.name) (vol)") : String(localized: "\(type.name) · nog \(available)")
    }

    private func field<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// "Je bent aangemeld" (of: op de wachtlijst), met Bekijk in Pasr.
struct EventSignupDone: View {
    let event: BusinessPasses.EventInfo
    let waitlist: Bool
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: waitlist ? "hourglass.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(waitlist ? Color.orange : Brand.mint)
            Text(waitlist ? "Je staat op de wachtlijst" : "Toegevoegd").font(.title.bold())
            Text(waitlist
                 ? String(localized: "Komt er een plek vrij, dan schuif je automatisch door. Je krijgt een melding en je ticket staat dan in Pasr.")
                 : (count == 1 ? String(localized: "Je ticket staat in Pasr, ook offline bij de hand. De dag ervoor krijg je een herinnering.")
                               : String(localized: "Je \(count) tickets staan naast elkaar in Pasr; veeg naar het volgende ticket.")))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            EventHeaderCard(event: event).frame(maxWidth: 380)
            Button(action: onOpen) {
                Label("Bekijk in Pasr", systemImage: "ticket").frame(maxWidth: 260).padding(.vertical, 6)
            }
            .pasrGlassButton(prominent: true)
            .tint(Brand.iris)
        }
    }
}

/// /add/t/<ticket>?c=<code>: een ticket dat zonder account is aangemeld (bijv. via de mail) aan je account koppelen.
struct TicketClaimSheet: View {
    let ticketID: String
    let code: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var busy = false
    @State private var error: String?
    @State private var added: String?

    private var signedIn: Bool { AccountService.shared.isSignedIn }
    private var existing: Card? { BusinessPasses.ticketCard(event: nil, ticket: added ?? ticketID, in: cards) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let card = existing {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Brand.mint)
                        Text(added == nil ? "Dit ticket staat al in je Pasr." : "Toegevoegd").font(.title2.bold())
                        TicketFaceView(card: card, layout: .front)
                            .aspectRatio(Brand.cardAspect, contentMode: .fit)
                            .frame(maxWidth: 380)
                        Button {
                            dismiss()
                            NotificationRouter.pendingCardID = card.id
                        } label: {
                            Label("Bekijk in Pasr", systemImage: "ticket").frame(maxWidth: 260).padding(.vertical, 6)
                        }
                        .pasrGlassButton(prominent: true)
                        .tint(Brand.iris)
                    } else {
                        Image(systemName: "ticket.fill").font(.system(size: 56)).foregroundStyle(Brand.iris)
                        Text("Ticket toevoegen aan Pasr").font(.title2.bold())
                        Text("Je ticket komt bij je account, zodat je het in Pasr en in Wallet hebt. Ook op je andere apparaten.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center)
                        }
                        if signedIn {
                            Button { Task { await claim() } } label: {
                                HStack {
                                    if busy { ProgressView() }
                                    Label("Toevoegen aan Pasr", systemImage: "plus")
                                }
                                .frame(maxWidth: 260).padding(.vertical, 6)
                            }
                            .pasrGlassButton(prominent: true)
                            .tint(Brand.iris)
                            .disabled(busy)
                        } else {
                            Text("Log eerst in met je Pasr-account (Instellingen › Account).")
                                .font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle(Text("Ticket"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluiten", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func claim() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let id = try await BusinessPasses.claim(ticket: ticketID, code: code, in: context)
            withAnimation { added = id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Onder een ticket van een zaak in de stapel: wat de status betekent.
struct EventTicketPanel: View {
    let card: Card
    let width: CGFloat

    var body: some View {
        let d = card.details
        if let i = info(d) {
            Label(i.0, systemImage: i.1)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(i.2)
                .padding(12)
                .frame(width: width, alignment: .leading)
                .background(Brand.inkRaised.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func info(_ d: CardDetails) -> (String, String, Color)? {
        let business = d.businessName ?? String(localized: "de organisator")
        if d.ticketCancelled {
            return (String(localized: "Dit event is geannuleerd door \(business). Je ticket is niet meer geldig."), "xmark.octagon.fill", Brand.coral)
        }
        if d.ticketWaitlist {
            return (String(localized: "Je staat op de wachtlijst. Komt er een plek vrij, dan krijg je een melding en is je ticket geldig."), "hourglass", Color.orange)
        }
        if d.ticketUsed {
            return (String(localized: "Gescand bij de ingang: dit ticket is gebruikt."), "checkmark.seal.fill", Color.secondary)
        }
        return nil
    }
}
