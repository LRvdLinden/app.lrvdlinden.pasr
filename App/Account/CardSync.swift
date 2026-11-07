import Foundation
import SwiftData
import SwiftUI

/// Keeps the cards in the Pasr account in step with this device. One round trip per sync: this device's
/// changes go up, everything that changed on the server since the last sync comes down. The newest change
/// of a card wins. The server stores every card encrypted. Photos of the card stay on the device (iCloud);
/// own logos travel along when they are small.
@MainActor
enum CardSync {
    private(set) static var isRunning = false
    static var lastError: String?

    private static func sinceKey(_ user: String) -> String { "pasr.sync.since.\(user)" }
    private static func pushedKey(_ user: String) -> String { "pasr.sync.pushed.\(user)" }

    static func lastSync(for user: String) -> Date? {
        let t = UserDefaults.standard.double(forKey: pushedKey(user))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func forget(userID: String) {
        UserDefaults.standard.removeObject(forKey: sinceKey(userID))
        UserDefaults.standard.removeObject(forKey: pushedKey(userID))
    }

    /// The moment a card last changed, including moving it to (or out of) Recently Deleted.
    static func changedAt(_ card: Card) -> Date { max(card.updatedAt, card.deletedAt ?? .distantPast) }

    static func sync(in context: ModelContext, account: AccountService = .shared) async {
        guard let user = account.session?.userID, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let started = Date.now
        let all = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let pushed = lastSync(for: user) ?? .distantPast
        // alleen privékaarten; kaarten in een gedeelde Pasr gaan via GroupService
        let changes = rows(all.filter { $0.groupID == nil && !$0.isTemporary && changedAt($0) > pushed })
        let since = UserDefaults.standard.string(forKey: sinceKey(user))
        var body: [String: Any] = ["changes": changes]
        if let since { body["since"] = since } else { body["since"] = NSNull() }
        do {
            guard let result = try await account.rpc("pasr_sync", body: body) as? [String: Any] else { return }
            apply(result["cards"] as? [[String: Any]] ?? [], to: all, in: context, group: nil)
            if let now = result["now"] as? String { UserDefaults.standard.set(now, forKey: sinceKey(user)) }
            UserDefaults.standard.set(started.timeIntervalSince1970, forKey: pushedKey(user))
            lastError = nil
            // eenmalig: land (regio-instelling) bij accounts van vóór build 20, voor de landentelling in het beheer
            let countryKey = "pasr.sync.country.\(user)"
            if !UserDefaults.standard.bool(forKey: countryKey), let country = AccountService.deviceCountry,
               (try? await account.rpc("pasr_set_country", body: ["p_country": country])) != nil {
                UserDefaults.standard.set(true, forKey: countryKey)
            }
            await GroupService.shared.sync(in: context)
            await UserPush.syncOnce()
            await LogoService.fillMissing(in: context)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Down

    /// Changes to send: id, moment and (unless deleted) the card itself.
    static func rows(_ cards: [Card]) -> [[String: Any]] {
        cards.map { card in
            var row: [String: Any] = ["id": card.id.uuidString, "updated_at": iso(changedAt(card)),
                                      "deleted": card.deletedAt != nil]
            if card.deletedAt == nil { row["card"] = payload(card) }
            return row
        }
    }

    /// `group`: the shared Pasr these rows come from (nil = the private cards).
    static func apply(_ rows: [[String: Any]], to existing: [Card], in context: ModelContext, group: UUID?) {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for row in rows {
            guard let idText = row["id"] as? String, let id = UUID(uuidString: idText),
                  let stamp = (row["updated_at"] as? String).flatMap(date) else { continue }
            let local = byID[id]
            if let local, local.groupID != group { continue }   // belongs to another place (private or another group)
            if let local, changedAt(local) >= stamp { continue }   // this device has the newer version
            if row["deleted"] as? Bool == true {
                if let local, local.deletedAt == nil {
                    local.deletedAt = stamp
                    changed = true
                }
                continue
            }
            guard let fields = row["card"] as? [String: Any] else { continue }
            let card = local ?? {
                let new = Card()
                new.id = id
                new.groupID = group
                context.insert(new)
                byID[id] = new
                return new
            }()
            fill(card, from: fields)
            card.deletedAt = nil
            card.updatedAt = stamp
            card.refreshCodeImage()
            changed = true
        }
        if changed { try? context.save() }
    }

    private static func fill(_ card: Card, from f: [String: Any]) {
        card.storeName = f["storeName"] as? String ?? card.storeName
        card.number = f["number"] as? String ?? card.number
        card.formatRaw = f["format"] as? String ?? card.formatRaw
        card.kindRaw = f["kind"] as? String ?? card.kindRaw
        card.colorHex = f["colorHex"] as? String ?? card.colorHex
        card.templateID = f["templateID"] as? String
        card.note = f["note"] as? String ?? ""
        card.isFavorite = f["isFavorite"] as? Bool ?? false
        card.isLocked = f["isLocked"] as? Bool ?? false
        card.useCount = max(card.useCount, f["useCount"] as? Int ?? 0)
        if let used = (f["lastUsed"] as? String).flatMap(date), used > (card.lastUsed ?? .distantPast) { card.lastUsed = used }
        if let created = (f["createdAt"] as? String).flatMap(date) { card.createdAt = created }
        card.balance = f["balance"] as? Double
        card.currencyCode = f["currencyCode"] as? String
        card.pin = f["pin"] as? String
        card.expiresAt = (f["expiresAt"] as? String).flatMap(date)
        card.website = f["website"] as? String
        card.balanceURL = f["balanceURL"] as? String
        // geschiedenis: de nieuwere versie wint voor uitgaven en opwaarderingen (zo blijft ongedaan maken staan);
        // "getoond" synchroniseert niet en blijft per apparaat, net als regels ouder dan wat er meekwam
        let remote: [CardEvent] = (f["history"] as? [[String: Any]] ?? []).compactMap { e in
            guard let id = (e["id"] as? String).flatMap(UUID.init(uuidString:)), let at = (e["date"] as? String).flatMap(date),
                  let kind = (e["kind"] as? String).flatMap(CardEvent.Kind.init(rawValue:)) else { return nil }
            return CardEvent(id: id, date: at, kind: kind, amount: e["amount"] as? Double, balance: e["balance"] as? Double,
                             place: e["place"] as? String)
        }
        if f["history"] != nil {   // oudere Pasr-versies sturen geen geschiedenis mee: dan blijft die van hier staan
            let oldest = remote.map(\.date).min()
            let ids = Set(remote.map(\.id))
            card.history = remote + card.history.filter { local in
                !ids.contains(local.id) && (local.kind == .shown || (oldest.map { local.date < $0 } ?? false))
            }
        }
        card.places = (f["places"] as? [[String: Any]] ?? []).compactMap { p in
            guard let lat = p["lat"] as? Double, let lon = p["lon"] as? Double else { return nil }
            return CardPlace(name: p["name"] as? String ?? "", latitude: lat, longitude: lon)
        }
        if let logo = (f["logo"] as? String).flatMap({ Data(base64Encoded: $0) }) {
            card.logoData = logo
            card.logoFromWebsite = false
        } else if f["ownLogo"] as? Bool != true, card.logoFromWebsite || card.logoData == nil {
            card.logoData = nil          // the store logo is filled in again from the app (LogoService)
            card.logoFromWebsite = false
        }
    }

    // MARK: Up

    private static func payload(_ c: Card) -> [String: Any] {
        var p: [String: Any] = [
            "storeName": c.storeName, "number": c.number, "format": c.formatRaw, "kind": c.kindRaw,
            "colorHex": c.colorHex, "note": c.note, "isFavorite": c.isFavorite, "isLocked": c.isLocked,
            "useCount": c.useCount, "createdAt": iso(c.createdAt),
        ]
        p["templateID"] = c.templateID
        p["lastUsed"] = c.lastUsed.map(iso)
        p["balance"] = c.balance
        p["currencyCode"] = c.currencyCode
        p["pin"] = c.pin
        p["expiresAt"] = c.expiresAt.map(iso)
        p["website"] = c.website
        p["balanceURL"] = c.balanceURL
        // altijd meesturen (ook leeg), zodat een ander apparaat weet dat de geschiedenis is bijgewerkt
        do {
            p["history"] = c.history.filter { $0.kind != .shown }.prefix(60).map { e -> [String: Any] in
                var d: [String: Any] = ["id": e.id.uuidString, "date": iso(e.date), "kind": e.kind.rawValue]
                d["amount"] = e.amount
                d["balance"] = e.balance
                d["place"] = e.place
                return d
            }
        }
        let places = c.places
        if !places.isEmpty {
            p["places"] = places.map { ["name": $0.name, "lat": $0.latitude, "lon": $0.longitude] }
        }
        if let logo = c.logoData, !c.logoFromWebsite {
            p["ownLogo"] = true
            if logo.count < 150_000 { p["logo"] = logo.base64EncodedString() }
        }
        return p
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    private static func iso(_ d: Date) -> String { formatter.string(from: d) }
    /// Postgres gives up to six decimals; the formatter reads at most three.
    private static func date(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return formatter.date(from: trimmed) ?? plain.date(from: trimmed)
    }
}

/// Runs a sync when the app opens, when it comes back to the front and shortly after cards change.
struct AccountSyncModifier: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var cards: [Card]
    private var account = AccountService.shared

    private var fingerprint: String {
        guard account.isSignedIn else { return "" }
        return cards.map { "\($0.id)\(CardSync.changedAt($0).timeIntervalSince1970)" }.sorted().joined()
    }

    func body(content: Content) -> some View {
        content
            .task(id: "\(account.session?.userID ?? "")|\(fingerprint)") {
                guard account.isSignedIn else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await CardSync.sync(in: context)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, account.isSignedIn { Task { await CardSync.sync(in: context) } }
            }
    }
}

extension View {
    func accountSync() -> some View { modifier(AccountSyncModifier()) }
}
