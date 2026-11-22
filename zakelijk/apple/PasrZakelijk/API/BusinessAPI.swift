import Foundation
import UIKit

/// Alle databasefuncties van Pasr Zakelijk (supabase/schema.sql, blok "zakelijk 1.0"). Rechten controleert de server.
@MainActor
enum BusinessAPI {
    private static var account: Account { .shared }

    /// Alle zaken waar je eigenaar of medewerker van bent.
    static func me() async throws -> [Business] {
        let json = try await account.rpc("pasr_business_me", [:])
        if let list = json as? [Any] {
            return list.compactMap { JSONObject($0) }.compactMap { Business(json: $0) }
        }
        guard let j = JSONObject(json) else { return [] }
        let many = j.array("businesses")
        if !many.isEmpty { return many.compactMap { Business(json: $0) } }
        if j.object("business") != nil, let one = Business(json: j) { return [one] }   // oude vorm: alleen je eigen zaak
        return []
    }

    static func register(name: String, city: String, website: String?, note: String?) async throws {
        _ = try await account.rpc("pasr_business_register",
                                  ["p_name": name, "p_city": city, "p_website": orNull(website), "p_note": orNull(note)])
    }

    private static func orNull(_ value: String?) -> Any {
        if let value, !value.isEmpty { return value }
        return NSNull()
    }

    // MARK: Kaarten (eigenaar)

    static func saveCard(_ card: BusinessCard, business: Business, logoChanged: Bool) async throws -> BusinessCard? {
        var p: [String: Any] = ["name": card.name, "reward": card.reward, "color": card.color.uppercased(),
                                "stamps_total": card.stampsTotal, "published": card.published, "business_id": business.id]
        if !card.id.isEmpty { p["id"] = card.id }
        if let text = card.textColor { p["text_color"] = text }
        if logoChanged || card.id.isEmpty { p["logo"] = orNull(card.logo) }
        let json = try await account.rpc("pasr_business_card_save", ["p_card": p])
        return JSONObject(json).flatMap { BusinessCard(json: $0) }
    }

    static func deleteCard(_ id: String) async throws {
        _ = try await account.rpc("pasr_business_card_delete", ["p_card": id])
    }

    static func members(card: String) async throws -> (total: Int, members: [MemberRow]) {
        let json = try await account.rpc("pasr_business_members_list", ["p_card": card, "p_limit": 200])
        guard let j = JSONObject(json) else { return (0, []) }
        let rows = j.array("members").enumerated().map { MemberRow(json: $0.element, index: $0.offset) }
        return (j.int("total") ?? rows.count, rows)
    }

    /// Huisstijl van de website van de zaak (Edge Function business-brand): naam, logo, kaartkleur, tekstkleur.
    /// Lukt het niet, dan nil (nooit een blokkerende fout).
    static func brand(business: String, url: String? = nil) async -> Brand? {
        var body: [String: Any] = ["business_id": business]
        if let url, !url.isEmpty { body["url"] = url }
        guard let json = try? await account.function("business-brand", body), let j = JSONObject(json) else { return nil }
        let b = j.object("brand") ?? j
        var brand = Brand(name: b.string("name", "site_name"), logo: nil, color: nil, textColor: nil,
                          source: b.string("source_url", "url", "source"))
        if let raw = b.string("logo"), let image = LogoImage.image(raw) { brand.logo = LogoImage.encode(image) }
        if let c = b.string("color", "theme_color").flatMap(Self.hex) { brand.color = c }
        if let t = b.string("text_color").flatMap(Self.hex) { brand.textColor = t }
        guard brand.logo != nil || brand.color != nil || brand.name != nil else { return nil }
        return brand
    }

    struct Brand {
        var name: String?
        var logo: String?
        var color: String?
        var textColor: String?
        var source: String?

        /// "kapsalon-anna.nl" uit de bron-URL.
        var domain: String? {
            guard let source, let host = URL(string: source)?.host() else { return nil }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    private static func hex(_ value: String) -> String? {
        var s = value.trimmingCharacters(in: .whitespaces).uppercased()
        if !s.hasPrefix("#") { s = "#" + s }
        if s.count == 4 { s = "#" + s.dropFirst().map { "\($0)\($0)" }.joined() }
        return s.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil ? s : nil
    }

    // MARK: Scannen (eigenaar en medewerkers)

    static func scan(_ code: String) async throws -> ScanResult {
        let json = try await account.rpc("pasr_business_scan", ["p_code": code])
        guard let r = ScanResult(json: json, code: code) else {
            throw APIError(String(localized: "Deze code is niet bekend. Laat de klant de kaart opnieuw tonen of typ de code over."))
        }
        return r
    }

    static func stamp(_ code: String, amount: Int) async throws -> ScanResult? {
        let json = try await account.rpc("pasr_business_stamp", ["p_code": code, "p_amount": amount, "p_device": deviceName])
        return ScanResult(json: json, code: code)
    }

    static func redeem(_ code: String) async throws -> ScanResult? {
        let json = try await account.rpc("pasr_business_redeem", ["p_code": code, "p_device": deviceName])
        return ScanResult(json: json, code: code)
    }

    static func undo(event: String, code: String) async throws -> ScanResult? {
        let json = try await account.rpc("pasr_business_undo", ["p_event": event, "p_device": deviceName])
        return ScanResult(json: json, code: code)
    }

    // MARK: Overzicht

    static func stats(business: String, days: Int) async throws -> (days: [DayStat], members: Int?) {
        let json = try await account.rpc("pasr_business_stats", ["p_business": business, "p_days": days])
        if let list = json as? [Any] { return (list.compactMap { JSONObject($0) }.compactMap { DayStat(json: $0) }, nil) }
        let j = JSONObject(json)
        return (j?.array("days", "stats").compactMap { DayStat(json: $0) } ?? [], j?.object("totals")?.int("members"))
    }

    static func log(business: String, limit: Int = 200) async throws -> [LogEvent] {
        let json = try await account.rpc("pasr_business_log", ["p_business": business, "p_limit": limit])
        if let list = json as? [Any] { return list.compactMap { JSONObject($0) }.compactMap { LogEvent(json: $0) } }
        return JSONObject(json)?.array("events", "log").compactMap { LogEvent(json: $0) } ?? []
    }

    // MARK: Medewerkers (eigenaar)

    static func staff(business: String) async throws -> [StaffMember] {
        let json = try await account.rpc("pasr_business_staff_list", ["p_business": business])
        if let list = json as? [Any] { return list.compactMap { JSONObject($0) }.compactMap { StaffMember(json: $0) } }
        return JSONObject(json)?.array("staff", "members").compactMap { StaffMember(json: $0) } ?? []
    }

    static func invite(business: String, name: String, email: String) async throws -> StaffInvite {
        let json = try await account.rpc("pasr_business_staff_invite", ["p_business": business, "p_name": name, "p_email": orNull(email)])
        guard let invite = StaffInvite(json: json) else { throw APIError(String(localized: "Er ging iets mis. Probeer het opnieuw.")) }
        return invite
    }

    /// Naam van de zaak bij een uitnodigingscode (mag zonder inloggen). nil als de code niet (meer) geldt.
    static func inviteInfo(code: String) async -> (business: String, city: String)? {
        guard let json = try? await account.rpc("pasr_business_staff_invite_info", ["p_code": code]),
              let j = JSONObject(json), j.string("status") == "ok", let name = j.string("business") else { return nil }
        return (name, j.string("city") ?? "")
    }

    /// Uitnodiging accepteren; geeft het id van de zaak terug (als de server dat meestuurt).
    static func accept(code: String) async throws -> String? {
        let json = try await account.rpc("pasr_business_staff_accept", ["p_code": code])
        guard let j = JSONObject(json) else { return json as? String }
        return j.object("business")?.string("id") ?? j.string("business_id", "business")
    }

    static func revoke(staff: String) async throws {
        _ = try await account.rpc("pasr_business_staff_revoke", ["p_staff": staff])
    }

    struct Settings {
        var cooldownMinutes: Int
        var maxPerScan: Int
        var listed: Bool
        var address: String
        var lat: Double?
        var lng: Double?
    }

    static func saveSettings(business: String, _ s: Settings) async throws {
        let settings: [String: Any] = ["cooldown_minutes": s.cooldownMinutes, "max_per_scan": s.maxPerScan, "listed": s.listed,
                                       "address": s.address, "lat": s.lat.map { $0 as Any } ?? NSNull(),
                                       "lng": s.lng.map { $0 as Any } ?? NSNull()]
        _ = try await account.rpc("pasr_business_settings_save", ["p_business": business, "p_settings": settings])
    }

    /// Korte naam van dit apparaat voor het logboek ("iPhone", "iPad"); geen persoonlijke naam.
    static var deviceName: String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        return UIDevice.current.model
        #endif
    }
}

/// Klantcode uit wat de camera of het toetsenbord oplevert: "PZ…", of een link met de code erin.
enum MemberCode {
    static let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    static func extract(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = t.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if let r = upper.range(of: "PZ[A-HJ-NP-Z2-9]{10,40}", options: .regularExpression) { return String(upper[r]) }
        // link met ?code= / ?lid= / #code
        if let url = URL(string: t), url.scheme != nil {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let v = items.first(where: { ["code", "lid", "member", "m"].contains($0.name.lowercased()) })?.value,
               let c = plain(v) { return c }
            if let f = url.fragment, let c = plain(f) { return c }
            return nil
        }
        return plain(upper)
    }

    private static func plain(_ s: String) -> String? {
        let u = s.uppercased()
        guard (12...48).contains(u.count), u.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil else { return nil }
        return u
    }
}
