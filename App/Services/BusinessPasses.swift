import Foundation
import SwiftData

/// Tickets (gratis events) en klantenkaarten met barcode van zaken in Pasr Zakelijk. De server is de bron
/// (pasr_my_event_tickets en pasr_my_member_cards, op je Pasr-account); Pasr zet ze als gewone kaarten in de stapel
/// (soort ticket en klantenkaart), zodat groeperen, vegen, widgets en de Watch vanzelf werken. Deze kaarten gaan niet
/// mee in de kaartsynchronisatie: elk apparaat haalt ze zelf op. Geboortedatum en e-mail komen nooit in de app-opslag.
@MainActor
enum BusinessPasses {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Ophalen en bijwerken

    private static var lastRun: Date?

    /// Tickets en klantenkaarten bijwerken (openen van de app, omlaag trekken, pushmelding). Hoogstens eens per minuut vanzelf.
    static func refreshAll(in context: ModelContext, force: Bool = false) async {
        guard AccountService.shared.isSignedIn else { return }
        if !force, let lastRun, Date.now.timeIntervalSince(lastRun) < 60 { return }
        lastRun = .now
        var changed = await refreshTickets(in: context)
        if await refreshMemberCards(in: context) { changed = true }
        if changed { try? context.save() }
    }

    /// Alle kaarten (ook verwijderde), om dubbele te voorkomen.
    private static func allCards(in context: ModelContext) -> [Card] {
        (try? context.fetch(FetchDescriptor<Card>())) ?? []
    }

    /// Rijen van een RPC die een lijst teruggeeft (ook als hij in een object zit).
    private static func rows(_ json: Any, key: String) -> [[String: Any]]? {
        if let list = json as? [[String: Any]] { return list }
        if let dict = json as? [String: Any] { return dict[key] as? [[String: Any]] ?? dict["rows"] as? [[String: Any]] }
        return nil
    }

    @discardableResult
    static func refreshTickets(in context: ModelContext) async -> Bool {
        guard let json = try? await AccountService.shared.rpc("pasr_my_event_tickets", body: [:]),
              let list = rows(json, key: "tickets") else { return false }
        let all = allCards(in: context)
        var changed = false
        var seen = Set<String>()
        for row in list {
            guard let ticketID = text(row, "ticket_id", "id")?.lowercased() else { continue }
            seen.insert(ticketID)
            let matches = all.filter { $0.details.ticketId?.lowercased() == ticketID }
            // dubbel (bijv. via iCloud van een ander apparaat): één houden
            for extra in matches.dropFirst() { context.delete(extra); changed = true }
            if let existing = matches.first {
                if existing.deletedAt != nil { continue }   // zelf weggehaald op dit apparaat
                if await apply(ticket: row, to: existing) { changed = true }
            } else if !Dismissed.contains(ticketID) {
                let card = Card(storeName: "", number: "", format: .qr, kind: .ticket, colorHex: "#6A5CFF")
                _ = await apply(ticket: row, to: card)
                context.insert(card)
                changed = true
            }
        }
        // niet meer op de server (bijv. afgemeld of op een ander account): weg uit de stapel
        for card in all where card.details.isEventTicket && !seen.contains(card.details.ticketId?.lowercased() ?? "") {
            WalletPass.removeRevokedPass(card)
            context.delete(card)
            changed = true
        }
        Dismissed.keepOnly(seen.union(memberIDs(all)))
        return changed
    }

    private static func memberIDs(_ cards: [Card]) -> Set<String> {
        Set(cards.compactMap { $0.details.memberId?.lowercased() })
    }

    /// Een ticketrij op de kaart zetten; true als er iets veranderde.
    private static func apply(ticket row: [String: Any], to card: Card) async -> Bool {
        let before = card.details
        var d = before
        d.issuer = "event"
        d.ticketId = text(row, "ticket_id", "id")?.lowercased()
        d.eventId = (text(row, "event_id") ?? text(row, "group_key"))?.lowercased()
        d.ticketStatus = text(row, "status")?.lowercased()
        d.holderName = text(row, "holder_name", "name")
        d.ticketTypeName = text(row, "ticket_type", "ticket_type_name")
        d.eventDate = MemberDiscount.date(row["starts_at"])
        d.eventEnd = MemberDiscount.date(row["ends_at"])
        d.doorsAt = MemberDiscount.date(row["doors_at"])
        d.address = text(row, "address")
        d.latitude = number(row["lat"] ?? row["latitude"])
        d.longitude = number(row["lng"] ?? row["longitude"])
        d.headerURL = https(text(row, "header_url"))
        d.businessName = text(row, "business_name")
        var changed = d != before
        if changed { card.details = d }
        let name = text(row, "event_name", "name") ?? String(localized: "Ticket")
        if card.storeName != name { card.storeName = name; changed = true }
        let code = text(row, "code") ?? ""
        if card.number != code || card.formatRaw != BarcodeFormat.qr.rawValue {
            card.number = code
            card.formatRaw = BarcodeFormat.qr.rawValue
            card.refreshCodeImage()
            changed = true
        }
        if card.kind != .ticket { card.kindRaw = CardKind.ticket.rawValue; changed = true }
        if let color = hex(text(row, "color")), color != card.colorHex.uppercased() { card.colorHex = color; changed = true }
        if await updateLogo(card, source: text(row, "business_logo", "logo")) { changed = true }
        if changed { card.updatedAt = .now }
        return changed
    }

    @discardableResult
    static func refreshMemberCards(in context: ModelContext) async -> Bool {
        guard let json = try? await AccountService.shared.rpc("pasr_my_member_cards", body: [:]),
              let list = rows(json, key: "cards") else { return false }
        let all = allCards(in: context)
        var changed = false
        var seen = Set<String>()
        for row in list {
            guard let memberID = text(row, "member_id")?.lowercased() else { continue }
            seen.insert(memberID)
            let matches = all.filter { $0.details.memberId?.lowercased() == memberID }
            for extra in matches.dropFirst() { context.delete(extra); changed = true }
            if let existing = matches.first {
                if existing.deletedAt != nil { continue }
                if await apply(member: row, to: existing) { changed = true }
            } else if !Dismissed.contains(memberID) {
                let card = Card(storeName: "", number: "", format: .code128, kind: .loyalty, colorHex: "#6A5CFF")
                _ = await apply(member: row, to: card)
                context.insert(card)
                changed = true
            }
        }
        for card in all where card.details.isMemberCard && !seen.contains(card.details.memberId?.lowercased() ?? "") {
            WalletPass.removeRevokedPass(card)
            context.delete(card)
            changed = true
        }
        return changed
    }

    /// Een klantenkaartrij op de kaart zetten; true als er iets veranderde.
    private static func apply(member row: [String: Any], to card: Card) async -> Bool {
        let before = card.details
        var d = before
        d.issuer = "member"
        d.memberId = text(row, "member_id")?.lowercased()
        d.memberCardId = text(row, "card_id")?.lowercased()
        d.businessName = text(row, "business_name")
        d.discountNow = MemberDiscount(json: row["discount_now"])
        d.nextDiscount = MemberDiscount(json: row["next_discount"])
        let saving = row["saving"] as? [String: Any]
        d.savingCount = saving.flatMap { number($0["count"]) }.map { Int($0) }
        d.savingTarget = saving.flatMap { number($0["target"]) }.map { Int($0) }
        d.savingReward = saving.flatMap { text($0, "reward") }
        d.savingCanRedeem = saving?["can_redeem"] as? Bool
        if let notify = (row["notify"] ?? row["notify_discounts"]) as? Bool { d.memberNotify = notify }
        var changed = d != before
        if changed { card.details = d }
        let name = text(row, "name", "card_name") ?? d.businessName ?? String(localized: "Klantenkaart")
        if card.storeName != name { card.storeName = name; changed = true }
        let cardNumber = text(row, "number") ?? ""
        let format = barcodeFormat(text(row, "barcode_type"), number: cardNumber)
        if card.number != cardNumber || card.format != format {
            card.number = cardNumber
            card.formatRaw = format.rawValue
            card.refreshCodeImage()
            changed = true
        }
        if card.kind != .loyalty { card.kindRaw = CardKind.loyalty.rawValue; changed = true }
        if let color = hex(text(row, "color")), color != card.colorHex.uppercased() { card.colorHex = color; changed = true }
        if await updateLogo(card, source: text(row, "logo", "business_logo")) { changed = true }
        if changed { card.updatedAt = .now }
        return changed
    }

    /// QR, Code 128 of EAN-13 (alleen een geldig EAN-13-nummer; anders Code 128 met hetzelfde nummer).
    static func barcodeFormat(_ raw: String?, number: String) -> BarcodeFormat {
        switch raw?.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") {
        case "qr": return .qr
        case "ean13":
            return number.count == 13 && number.allSatisfy(\.isNumber)
                && BarcodeEncoder.gs1CheckDigit(String(number.prefix(12))) == Int(String(number.last!)) ? .ean13 : .code128
        default: return .code128
        }
    }

    private static func updateLogo(_ card: Card, source: String?) async -> Bool {
        guard let source, !source.isEmpty, card.details.logoSource != source || card.logoData == nil,
              let data = await BusinessCards.logoData(source) else { return false }
        card.logoData = data
        card.logoFromWebsite = false
        var d = card.details
        d.logoSource = source
        card.details = d
        return true
    }

    // MARK: Events

    /// pasr_event_public: alles over het event zonder persoonsgegevens.
    struct EventInfo {
        struct TicketType: Identifiable, Hashable {
            var id: String
            var name: String
            var available: Int?
        }
        var id: String
        var name: String
        var description: String?
        var start: Date?
        var end: Date?
        var doors: Date?
        var address: String?
        var latitude: Double?
        var longitude: Double?
        var color: String
        var header: URL?
        var business: String?
        var logo: String?
        var types: [TicketType]
        var spotsLeft: Int?
        var maxPerPerson: Int
        var signupOpen: Bool
        var waitlist: Bool
        var status: String?

        init?(json: Any?, id: String) {
            var dict = json as? [String: Any]
            if dict == nil, let list = json as? [[String: Any]] { dict = list.first }
            guard let d = dict, d["name"] != nil || d["id"] != nil else { return nil }
            self.id = BusinessPasses.text(d, "id") ?? id
            name = BusinessPasses.text(d, "name") ?? String(localized: "Event")
            description = BusinessPasses.text(d, "description")
            start = MemberDiscount.date(d["starts_at"])
            end = MemberDiscount.date(d["ends_at"])
            doors = MemberDiscount.date(d["doors_at"])
            address = BusinessPasses.text(d, "address")
            latitude = BusinessPasses.number(d["lat"])
            longitude = BusinessPasses.number(d["lng"])
            color = BusinessPasses.hex(BusinessPasses.text(d, "color")) ?? "#6A5CFF"
            header = BusinessPasses.https(BusinessPasses.text(d, "header_url")).flatMap(URL.init(string:))
            business = BusinessPasses.text(d, "business_name")
            logo = BusinessPasses.text(d, "business_logo", "logo")
            types = (d["ticket_types"] as? [[String: Any]] ?? []).compactMap { t in
                guard let id = BusinessPasses.text(t, "id") else { return nil }
                return TicketType(id: id, name: BusinessPasses.text(t, "name") ?? String(localized: "Toegang"),
                                  available: BusinessPasses.number(t["available"]).map { Int($0) })
            }
            spotsLeft = BusinessPasses.number(d["spots_left"]).map { Int($0) }
            maxPerPerson = max(1, BusinessPasses.number(d["max_per_person"]).map { Int($0) } ?? 4)
            signupOpen = d["signup_open"] as? Bool ?? true
            waitlist = d["waitlist"] as? Bool ?? false
            status = BusinessPasses.text(d, "status")?.lowercased()
        }

        var isCancelled: Bool { status == "cancelled" }
        var isFull: Bool { (spotsLeft ?? 1) <= 0 }

        /// "za 19 dec 2026 · 16:00 – 19:00"
        var whenText: String? {
            guard let start else { return nil }
            var s = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()) + " · "
                + start.formatted(date: .omitted, time: .shortened)
            if let end, end > start, Calendar.current.isDate(end, inSameDayAs: start) {
                s += " – " + end.formatted(date: .omitted, time: .shortened)
            }
            return s
        }
    }

    static func event(id: String) async throws -> EventInfo {
        let json = try await AccountService.shared.publicRPC("pasr_event_public", body: ["p_event": id])
        guard let info = EventInfo(json: json, id: id) else {
            throw Failure(message: String(localized: "Dit event is niet (meer) gevonden."))
        }
        return info
    }

    struct Registration {
        var waitlist: Bool
        var ticketIDs: [String]
    }

    /// Aanmelden (ingelogd): de tickets komen meteen in je Pasr.
    static func register(event: String, firstName: String, lastName: String, email: String, birthDate: Date,
                         ticketType: String?, count: Int, in context: ModelContext) async throws -> Registration {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.dateFormat = "yyyy-MM-dd"
        var body: [String: Any] = [
            "p_event": event,
            "p_first_name": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_last_name": lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "p_birth_date": day.string(from: birthDate),
            "p_count": count,
        ]
        body["p_ticket_type"] = ticketType ?? NSNull()
        let json = try await AccountService.shared.rpc("pasr_event_register", body: body)
        let d = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first ?? [:]
        let tickets = (d["tickets"] as? [[String: Any]] ?? []).compactMap { text($0, "ticket_id")?.lowercased() }
        for id in tickets { Dismissed.remove(id) }
        _ = await refreshTickets(in: context)
        await UserPush.enable()   // herinnering de dag ervoor, wijzigingen, wachtlijst
        try? context.save()
        return Registration(waitlist: (text(d, "status") ?? "").lowercased() == "waitlist", ticketIDs: tickets)
    }

    /// /add/t/<ticket>?c=<code>: een ticket (aangemeld zonder account) aan je account koppelen.
    static func claim(ticket: String, code: String, in context: ModelContext) async throws -> String {
        let json = try await AccountService.shared.rpc("pasr_event_ticket_claim", body: ["p_ticket": ticket, "p_code": code])
        let id = ((json as? [String: Any]).flatMap { text($0, "ticket_id") } ?? ticket).lowercased()
        Dismissed.remove(id)
        _ = await refreshTickets(in: context)
        try? context.save()
        return id
    }

    // MARK: Klantenkaarten

    struct MemberCardInfo {
        var id: String
        var name: String
        var color: String
        var logo: String?
        var business: String?
        var summary: String?
        var discountNow: MemberDiscount?
        var nextDiscount: MemberDiscount?

        init?(json: Any?, id: String) {
            var dict = json as? [String: Any]
            if dict == nil, let list = json as? [[String: Any]] { dict = list.first }
            guard let d = dict, d["name"] != nil || d["id"] != nil else { return nil }
            self.id = BusinessPasses.text(d, "id") ?? id
            name = BusinessPasses.text(d, "name") ?? String(localized: "Klantenkaart")
            color = BusinessPasses.hex(BusinessPasses.text(d, "color")) ?? "#6A5CFF"
            logo = BusinessPasses.text(d, "logo", "business_logo")
            business = BusinessPasses.text(d, "business_name")
            if let s = d["goals_summary"] as? String {
                summary = s
            } else if let list = d["goals_summary"] as? [String] {
                summary = list.joined(separator: " · ")
            }
            discountNow = MemberDiscount(json: d["discount_now"])
            nextDiscount = MemberDiscount(json: d["next_discount"])
        }
    }

    static func memberCard(id: String) async throws -> MemberCardInfo {
        let json = try await AccountService.shared.publicRPC("pasr_member_card_public", body: ["p_card": id])
        guard let info = MemberCardInfo(json: json, id: id) else {
            throw Failure(message: String(localized: "Deze klantenkaart is niet (meer) gevonden."))
        }
        return info
    }

    /// Aansluiten bij een klantenkaart; geeft de kaart in Pasr. Al lid: gewoon de bestaande kaart.
    static func join(card cardID: String, shareName: Bool, in context: ModelContext) async throws -> Card {
        var joinError: Error?
        do {
            let json = try await AccountService.shared.rpc("pasr_member_card_join", body: ["p_card": cardID, "p_share_name": shareName])
            if let id = ((json as? [String: Any]).flatMap { text($0, "member_id") })?.lowercased() { Dismissed.remove(id) }
        } catch {
            joinError = error   // bijv. al lid: dan staat hij hieronder gewoon in de lijst
        }
        let all = allCards(in: context)
        for card in all where card.details.memberCardId == cardID.lowercased() && card.deletedAt != nil {
            if let id = card.details.memberId { Dismissed.remove(id) }
            context.delete(card)
        }
        _ = await refreshMemberCards(in: context)
        try? context.save()
        if let card = allCards(in: context).first(where: { $0.deletedAt == nil && $0.details.memberCardId == cardID.lowercased() }) {
            return card
        }
        throw joinError ?? Failure(message: String(localized: "Toevoegen lukte niet. Probeer het later opnieuw."))
    }

    static func setNotify(_ card: Card, on: Bool) async throws {
        guard let member = card.details.memberId else { return }
        _ = try await AccountService.shared.rpc("pasr_member_card_notify", body: ["p_member": member, "p_on": on])
        var d = card.details
        d.memberNotify = on
        card.details = d
        if on { await UserPush.enable() }
    }

    /// Kaart of ticket is in Pasr verwijderd: een klantenkaart ook bij de zaak opzeggen; niet opnieuw ophalen.
    static func didDelete(_ card: Card) {
        let d = card.details
        if d.isEventTicket, let id = d.ticketId { Dismissed.insert(id) }
        if d.isMemberCard, let member = d.memberId {
            Dismissed.insert(member)
            Task { _ = try? await AccountService.shared.rpc("pasr_member_card_leave", body: ["p_member": member]) }
        }
        if d.isServerItem { WalletPass.removeRevokedPass(card) }
    }

    // MARK: Zoeken voor meldingen en links

    static func ticketCard(event: String?, ticket: String?, in cards: [Card]) -> Card? {
        let live = cards.filter { $0.deletedAt == nil && $0.details.isEventTicket }
        if let ticket, let c = live.first(where: { $0.details.ticketId == ticket.lowercased() }) { return c }
        guard let event else { return nil }
        return live.filter { $0.details.eventId == event.lowercased() }.alphabetical().first
    }

    static func memberCard(card: String?, in cards: [Card]) -> Card? {
        guard let card else { return nil }
        return cards.first { $0.deletedAt == nil && $0.details.memberCardId == card.lowercased() }
    }

    // MARK: Hulpjes

    nonisolated static func text(_ d: [String: Any], _ keys: String...) -> String? {
        for k in keys {
            if let v = d[k] as? String {
                let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return String(t.prefix(300)) }
            } else if let v = d[k] as? NSNumber {
                return v.stringValue
            }
        }
        return nil
    }

    nonisolated static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    nonisolated static func hex(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let clean = raw.hasPrefix("#") ? raw : "#" + raw
        return clean.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? clean.uppercased() : nil
    }

    nonisolated static func https(_ value: String?) -> String? {
        guard let value, value.lowercased().hasPrefix("https://"), URL(string: value) != nil else { return nil }
        return value
    }

    /// Tickets en klantenkaarten die je zelf uit Pasr haalde (niet opnieuw toevoegen bij de volgende verversing).
    enum Dismissed {
        private static let key = "pasr.business.dismissed"
        private static var all: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        static func contains(_ id: String) -> Bool { all.contains(id.lowercased()) }
        static func insert(_ id: String) { UserDefaults.standard.set(Array(all.union([id.lowercased()])), forKey: key) }
        static func remove(_ id: String) { UserDefaults.standard.set(Array(all.subtracting([id.lowercased()])), forKey: key) }
        /// Alleen ids die de server nog kent bewaren (anders groeit de lijst eindeloos).
        static func keepOnly(_ ids: Set<String>) {
            let kept = all.filter { ids.contains($0) }
            if kept.count != all.count { UserDefaults.standard.set(Array(kept), forKey: key) }
        }
    }
}
