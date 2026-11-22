import Foundation
import SwiftData
import UserNotifications

/// Pasr voor ondernemers: zakelijke stempelkaarten. Je meldt je aan via de join-link of QR-code van de zaak
/// (pasr_business_join) en krijgt een eigen klantcode; die laat je scannen (QR op de achterkant). De zaak zet de
/// stempels, Pasr haalt de stand op met pasr_business_member (bij openen en omlaag trekken). Niets persoonlijks:
/// de server kent alleen de code en de stand.
@MainActor
enum BusinessCards {
    /// Wat de server over een zakelijke kaart zegt. Alles optioneel; meerdere namen voor hetzelfde veld, zodat een
    /// kleine naamswijziging op de server de app niet breekt.
    struct Info {
        var cardID: String?
        var memberCode: String?
        var name: String?
        var business: String?
        var logo: String?
        var colorHex: String?
        var kind: String?
        var stampsTotal: Int?
        var stampsCount: Int?
        var reward: String?
        var active = true

        init?(json: Any?) {
            var dict = json as? [String: Any]
            if dict == nil, let list = json as? [[String: Any]] { dict = list.first }   // een functie die een rij teruggeeft
            guard let d = dict else { return nil }
            func text(_ keys: String...) -> String? {
                for k in keys { if let v = d[k] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty { return v } }
                return nil
            }
            func int(_ keys: String...) -> Int? {
                for k in keys { if let v = d[k] as? NSNumber { return v.intValue } else if let v = d[k] as? String, let i = Int(v) { return i } }
                return nil
            }
            let card = d["card"] as? [String: Any]
            cardID = text("business_card_id", "card_id", "id") ?? (card?["id"] as? String)
            memberCode = text("member_code", "code")
            name = text("name", "card_name", "title") ?? (card?["name"] as? String)
            business = text("business_name", "business", "zaak") ?? ((d["business"] as? [String: Any])?["name"] as? String)
            logo = text("logo", "logo_url") ?? (card?["logo"] as? String)
            colorHex = text("color", "card_hex", "colour", "color_hex") ?? (card?["color"] as? String)
            kind = text("kind", "type")
            stampsTotal = int("stamps_total", "stampsTotal", "total") ?? (card?["stamps_total"] as? NSNumber)?.intValue
            stampsCount = int("stamps_count", "stampsCount", "stamps", "count")
            reward = text("reward") ?? (card?["reward"] as? String)
            if d["published"] as? Bool == false { active = false }
            if let status = text("status")?.lowercased(), ["blocked", "removed", "unpublished", "inactive"].contains(status) { active = false }
        }

        /// Naam op de kaart: de zaak, anders de naam van de kaart.
        var displayName: String { business ?? name ?? String(localized: "Stempelkaart") }

        var color: String? {
            guard let hex = colorHex?.trimmingCharacters(in: .whitespaces) else { return nil }
            let clean = hex.hasPrefix("#") ? hex : "#" + hex
            return clean.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil ? clean.uppercased() : nil
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Kaartinfo vóór het aanmelden (pasr_business_card). Bestaat de functie niet of is de kaart onbekend: nil.
    static func preview(cardID: String) async -> Info? {
        guard let json = try? await AccountService.shared.publicRPC("pasr_business_card", body: ["p_card": cardID]) else { return nil }
        return Info(json: json)
    }

    /// Stand van een klantcode (pasr_business_member).
    static func member(code: String) async throws -> Info {
        let json = try await AccountService.shared.publicRPC("pasr_business_member", body: ["p_code": code])
        guard let info = Info(json: json) else {
            throw Failure(message: String(localized: "Deze stempelkaart is niet (meer) bekend bij de zaak."))
        }
        return info
    }

    /// Aanmelden: nieuwe klantcode, stand ophalen en de kaart in Pasr zetten.
    static func join(cardID: String, preview: Info?, in context: ModelContext) async throws -> Card {
        let json = try await AccountService.shared.publicRPC("pasr_business_join", body: ["p_card": cardID])
        let joined = Info(json: json)
        let code = (json as? String) ?? joined?.memberCode
        guard let code, !code.isEmpty, code.count <= 120 else {
            throw Failure(message: String(localized: "Aanmelden bij deze stempelkaart lukte niet. Probeer het later opnieuw."))
        }
        let info = (try? await member(code: code)) ?? joined ?? preview
        let card = Card(storeName: info?.displayName ?? preview?.displayName ?? String(localized: "Stempelkaart"),
                        number: code, format: .qr, kind: .stamps,
                        colorHex: info?.color ?? preview?.color ?? Brand.palette.first ?? "#6A5CFF")
        var d = CardDetails()
        d.issuer = "business"
        d.businessCardId = cardID.lowercased()
        d.memberCode = code
        d.stampsTotal = info?.stampsTotal ?? preview?.stampsTotal ?? CardDetails.defaultStamps
        d.stampsCount = info?.stampsCount ?? 0
        d.reward = info?.reward ?? preview?.reward
        card.details = d
        if let logo = await logoData(info?.logo ?? preview?.logo) { card.logoData = logo }
        card.refreshCodeImage()
        context.insert(card)
        try? context.save()
        return card
    }

    /// Stand van één zakelijke kaart bijwerken. Geeft true als er iets veranderde.
    @discardableResult
    static func refresh(_ card: Card) async -> Bool {
        let before = card.details
        guard before.isBusiness, let code = before.memberCode, let info = try? await member(code: code) else { return false }
        var d = before
        if let total = info.stampsTotal { d.stampsTotal = min(max(total, CardDetails.stampsRange.lowerBound), CardDetails.stampsRange.upperBound) }
        if let count = info.stampsCount { d.stampsCount = max(0, count) }
        if let reward = info.reward { d.reward = reward }
        var changed = d != before
        if changed { card.details = d }
        if let color = info.color, color != card.colorHex.uppercased() { card.colorHex = color; changed = true }
        if card.logoData == nil, let logo = await logoData(info.logo) { card.logoData = logo; changed = true }
        guard changed else { return false }
        card.updatedAt = .now
        if !before.stampsFull && d.stampsFull { StampAlerts.cardFull(card) }
        Task { await WalletPass.refreshIfInWallet(card) }
        return true
    }

    /// Alle zakelijke kaarten (bij openen van de app en omlaag trekken). Hoogstens eens per 2 minuten vanzelf.
    private static var lastRun: Date?
    static func refreshAll(in context: ModelContext, force: Bool = false) async {
        if !force, let lastRun, Date.now.timeIntervalSince(lastRun) < 120 { return }
        lastRun = .now
        let all = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate<Card> { $0.deletedAt == nil }))) ?? []
        var changed = false
        for card in all where card.kind == .stamps && card.details.isBusiness {
            if await refresh(card) { changed = true }
        }
        if changed { try? context.save() }
    }

    /// Logo van de server: base64 (PNG) of een https-adres.
    private static func logoData(_ value: String?) async -> Data? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("https://"), let url = URL(string: value) {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 600_000 else { return nil }
            return data
        }
        let raw = value.components(separatedBy: ",").last ?? value   // ook "data:image/png;base64,…"
        guard let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters), data.count < 600_000 else { return nil }
        return data
    }
}

/// Melding als een stempelkaart vol is (eigen kaart na je laatste tik, of een zakelijke kaart na het ophalen).
enum StampAlerts {
    @MainActor
    static func cardFull(_ card: Card) {
        let details = card.details
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Je stempelkaart van \(card.storeName) is vol")
        content.body = details.reward?.nilIfEmpty.map { String(localized: "Wissel je beloning in: \($0).") }
            ?? String(localized: "Wissel je beloning in bij je volgende bezoek.")
        content.sound = .default
        content.threadIdentifier = "stamps"
        content.userInfo = ["cardID": card.id.uuidString]
        let request = UNNotificationRequest(identifier: "stamps-full-\(card.id.uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        Task {
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined { await Reminders.requestPermission() }
            try? await center.add(request)
        }
    }
}
