import Foundation
import SwiftData
import SwiftUI

/// Tijdelijk delen: een kaart delen tot een einddatum. De kaart gaat versleuteld naar de Pasr-server onder een
/// willekeurige code; de link is https://pasr.nl/tijdelijk/#<code>. De ontvanger voegt hem toe aan Pasr. Na het
/// einde (of als de deler eerder stopt) toont Pasr de code niet meer en geeft de server de kaart niet meer uit.
/// Tijdelijke kaarten gaan niet naar Apple Wallet, de Watch, widgets, back-ups of je account, en je kunt ze niet
/// verder delen. Werkt ook zonder account.
@MainActor
enum TempShare {
    static let webBase = "https://pasr.nl/tijdelijk/"
    static let maxDays = 90

    /// Wat ik zelf tijdelijk heb gedeeld (alleen op dit apparaat): nodig om eerder te kunnen stoppen.
    struct Sent: Codable, Identifiable, Equatable {
        var token: String
        var key: String
        var cardID: UUID
        var storeName: String
        var until: Date
        var revoked = false
        var id: String { token }
        var isActive: Bool { !revoked && until > .now }
        var url: URL { URL(string: TempShare.webBase + "#" + token)! }
    }

    enum Fetched {
        case ok(fields: [String: Any], until: Date)
        case expired(Date?)
        case revoked
        case notFound
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Delen

    /// Maakt de tijdelijke link. Logo, foto's en notitie gaan niet mee; bij een voucher wel saldo en pincode.
    static func create(for card: Card, until: Date) async throws -> Sent {
        guard AccountConfig.isConfigured else {
            throw Failure(message: String(localized: "Tijdelijk delen is in deze versie nog niet beschikbaar."))
        }
        var fields: [String: Any] = [
            "storeName": card.storeName, "number": card.number, "format": card.formatRaw, "kind": card.kindRaw,
            "colorHex": card.colorHex,
        ]
        fields["templateID"] = card.templateID
        fields["website"] = card.website ?? card.logoDomain
        if card.kind == .voucher {
            fields["balance"] = card.balance
            fields["currencyCode"] = card.currencyCode
            fields["pin"] = card.pin
            fields["expiresAt"] = card.expiresAt.map { ISO8601DateFormatter().string(from: $0) }
        }
        let body: [String: Any] = ["p_card": fields, "p_expires": ISO8601DateFormatter().string(from: until)]
        guard let json = try await AccountService.shared.publicRPC("pasr_temp_share_create", body: body) as? [String: Any],
              let token = json["token"] as? String, let key = json["key"] as? String else {
            throw Failure(message: String(localized: "Er ging iets mis. Probeer het opnieuw."))
        }
        let sent = Sent(token: token, key: key, cardID: card.id, storeName: card.storeName, until: until)
        save(sent: [sent] + allSent())
        return sent
    }

    static func stop(_ sent: Sent) async throws {
        _ = try await AccountService.shared.publicRPC("pasr_temp_share_revoke", body: ["p_token": sent.token, "p_key": sent.key])
        var list = allSent()
        if let i = list.firstIndex(where: { $0.token == sent.token }) { list[i].revoked = true }
        save(sent: list)
    }

    /// Einddatum wijzigen: langer delen, korter, of (met een datum in het verleden) nu laten verlopen. Kan zolang de
    /// kaart nog op de server staat (tot het nachtelijk opruimen na het einde).
    static func update(_ sent: Sent, until: Date) async throws -> Sent {
        guard let json = try await AccountService.shared.publicRPC(
            "pasr_temp_share_update",
            body: ["p_token": sent.token, "p_key": sent.key, "p_expires": ISO8601DateFormatter().string(from: until)]) as? [String: Any]
        else { throw Failure(message: String(localized: "Er ging iets mis. Probeer het opnieuw.")) }
        guard json["ok"] as? Bool == true else {
            throw Failure(message: String(localized: "Deze kaart staat niet meer op de server. Deel hem opnieuw."))
        }
        var updated = sent
        updated.until = (json["expires_at"] as? String).flatMap(parse) ?? until
        var list = allSent()
        if let i = list.firstIndex(where: { $0.token == sent.token }) { list[i] = updated }
        save(sent: list)
        return updated
    }

    /// Alleen uit het overzicht op dit apparaat halen (verandert niets bij de ander).
    static func forget(_ sent: Sent) {
        save(sent: allSent().filter { $0.token != sent.token })
    }

    private static let sentKey = "pasr.tempshare.sent"

    static func allSent() -> [Sent] {
        guard let data = UserDefaults.standard.data(forKey: sentKey),
              let list = try? JSONDecoder().decode([Sent].self, from: data) else { return [] }
        // verlopen langer dan een week geleden: niet meer bewaren
        return list.filter { $0.until > .now.addingTimeInterval(-7 * 86_400) }
    }

    static func sent(for card: Card) -> [Sent] { allSent().filter { $0.cardID == card.id } }

    private static func save(sent: [Sent]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(sent), forKey: sentKey)
    }

    // MARK: Ontvangen

    /// https://pasr.nl/tijdelijk/#<code> en pasr://tijdelijk#<code>
    static func token(from url: URL) -> String? {
        let isWeb = url.host() == "pasr.nl" && url.path().hasPrefix("/tijdelijk")
        let isApp = url.scheme == "pasr" && url.host() == "tijdelijk"
        guard isWeb || isApp, let fragment = url.fragment(), (16...40).contains(fragment.count),
              fragment.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return fragment
    }

    static func fetch(_ token: String) async throws -> Fetched {
        guard let json = try await AccountService.shared.publicRPC("pasr_temp_share_get", body: ["p_token": token]) as? [String: Any] else {
            return .notFound
        }
        let until = (json["expires_at"] as? String).flatMap(parse)
        switch json["status"] as? String {
        case "ok":
            guard let fields = json["card"] as? [String: Any], let until else { return .notFound }
            return .ok(fields: fields, until: until)
        case "expired": return .expired(until)
        case "revoked": return .revoked
        default: return .notFound
        }
    }

    static func makeCard(token: String, fields f: [String: Any], until: Date) -> Card {
        let card = Card(storeName: f["storeName"] as? String ?? "", number: f["number"] as? String ?? "",
                        format: BarcodeFormat(rawValue: f["format"] as? String ?? "") ?? .code128,
                        kind: CardKind(rawValue: f["kind"] as? String ?? "") ?? .loyalty,
                        colorHex: f["colorHex"] as? String ?? "#6A5CFF")
        card.templateID = f["templateID"] as? String
        card.website = f["website"] as? String
        card.balance = f["balance"] as? Double
        card.currencyCode = f["currencyCode"] as? String
        card.pin = f["pin"] as? String
        card.expiresAt = (f["expiresAt"] as? String).flatMap(parse)
        card.shareToken = token
        card.sharedUntil = until
        card.refreshCodeImage()
        return card
    }

    /// Volgt wat de deler doet: verlengd, korter gemaakt, nu laten verlopen of gestopt. Een verlengde kaart waarvan de
    /// code al was gewist, wordt opnieuw opgehaald.
    static func refreshStatuses(in context: ModelContext) async {
        let all = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.shareToken != nil && $0.deletedAt == nil }))) ?? []
        // gestopte kaarten blijven gestopt; verlopen kaarten tot 8 dagen terug kunnen nog verlengd zijn
        let watch = all.filter { !$0.shareRevoked && ($0.sharedUntil ?? .distantPast) > .now.addingTimeInterval(-8 * 86_400) }
        guard !watch.isEmpty,
              let json = try? await AccountService.shared.publicRPC("pasr_temp_share_info",
                                                                  body: ["p_tokens": watch.compactMap(\.shareToken)]) as? [String: Any]
        else { return }
        var changed = false
        for card in watch {
            guard let token = card.shareToken, let info = json[token] as? [String: Any], let status = info["status"] as? String else { continue }
            let until = (info["expires_at"] as? String).flatMap(parse)
            switch status {
            case "ok":
                if let until, until != card.sharedUntil { card.sharedUntil = until; changed = true }
                if card.number.isEmpty, case .ok(let fields, let serverUntil)? = try? await fetch(token) {
                    let fresh = makeCard(token: token, fields: fields, until: serverUntil)
                    card.number = fresh.number
                    card.formatRaw = fresh.formatRaw
                    card.pin = fresh.pin
                    card.balance = fresh.balance
                    card.sharedUntil = serverUntil
                    card.refreshCodeImage()
                    changed = true
                }
            case "expired":
                if let until, until < (card.sharedUntil ?? .distantFuture) { card.sharedUntil = until; changed = true }
            default:   // revoked of niet meer op de server
                card.shareRevoked = true
                card.codeImage = nil
                changed = true
            }
        }
        if changed {
            try? context.save()
            scrubExpired(in: context)
        }
    }

    /// Verlopen tijdelijke kaarten: de opgeslagen QR-afbeelding weg, zodat de code ook niet meer in de app zit.
    static func scrubExpired(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.shareToken != nil }))) ?? []
        var changed = false
        for card in all where card.isShareExpired && (card.codeImage != nil || !card.number.isEmpty) {
            card.codeImage = nil
            card.number = ""
            card.pin = nil
            changed = true
        }
        if changed { try? context.save() }
    }

    private static func parse(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: trimmed) ?? ISO8601DateFormatter().date(from: trimmed)
    }
}
