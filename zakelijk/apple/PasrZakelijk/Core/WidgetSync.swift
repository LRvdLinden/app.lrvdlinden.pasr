import Foundation
import Observation
import WidgetKit

/// Werkt de cache van de widgets bij (Vandaag, Komend event, Te doen) na het laden van je zaken, bij openen van de app en
/// na verversen. Alleen goedgekeurde zaken; een medewerker krijgt wat de server hem laat zien (geen fout bij weigeren).
@MainActor
enum WidgetSync {
    private static var lastRun = Date.distantPast
    private static var running = false

    static func refresh(force: Bool = false) async {
        let businesses = BusinessStore.shared.businesses.filter(\.isApproved)
        guard Account.shared.isSignedIn, !businesses.isEmpty else { return }
        guard !running, force || Date.now.timeIntervalSince(lastRun) > 60 else { return }
        running = true
        defer { running = false; lastRun = .now }
        var out: [WidgetSnapshot.Business] = []
        for business in businesses.prefix(10) {
            out.append(await snapshot(for: business))
        }
        if WidgetStore.save(WidgetSnapshot(updatedAt: .now, businesses: out)) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        await LocalNotices.check(out)
    }

    /// Uitloggen: widgets leeg.
    static func clear() {
        WidgetStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func snapshot(for business: Business) async -> WidgetSnapshot.Business {
        let numbers = await todayNumbers(business)
        let upcoming = await nextEvent(business)
        let tasks = await todoItems(business)
        return WidgetSnapshot.Business(id: business.id, name: business.name, isOwner: business.isOwner,
                                       today: numbers, event: upcoming, todo: tasks)
    }

    // MARK: Vandaag

    private static func todayNumbers(_ business: Business) async -> WidgetSnapshot.Today {
        let empty = WidgetSnapshot.Today(stamps: 0, rewards: 0, joins: 0, trend: Array(repeating: 0, count: 7), lastWeekStamps: nil)
        guard business.isOwner, let stats = try? await BusinessAPI.stats(business: business.id, days: 14) else { return empty }
        let cal = TKFormat.calendar
        let byDay = Dictionary(stats.days.map { (cal.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { a, _ in a })
        let start = cal.startOfDay(for: .now)
        func day(_ offset: Int) -> DayStat? {
            cal.date(byAdding: .day, value: -offset, to: start).flatMap { byDay[$0] }
        }
        let now = day(0)
        return WidgetSnapshot.Today(stamps: now?.stamps ?? 0, rewards: now?.rewards ?? 0, joins: now?.joins ?? 0,
                                    trend: (0..<7).reversed().map { day($0)?.stamps ?? 0 },
                                    lastWeekStamps: stats.days.isEmpty ? nil : (day(7)?.stamps ?? 0))
    }

    // MARK: Komend event

    private static func nextEvent(_ business: Business) async -> WidgetSnapshot.Event? {
        guard let events = try? await TKAPI.events(business: business.id) else { return nil }
        guard let e = events.filter({ $0.isPublished && !$0.isCancelled && $0.endsAt > .now })
            .min(by: { $0.startsAt < $1.startsAt }) else { return nil }
        return WidgetSnapshot.Event(id: e.id, name: e.name, startsAt: e.startsAt, endsAt: e.endsAt,
                                    registered: e.registered, checkedIn: e.checkedIn, capacity: e.capacity)
    }

    // MARK: Te doen

    private static func todoItems(_ business: Business) async -> [WidgetSnapshot.TodoItem] {
        guard business.isOwner else { return [] }
        var items: [WidgetSnapshot.TodoItem] = []
        let soon = Date.now.addingTimeInterval(7 * 86_400)

        // open uitnodigingen voor gezamenlijke acties
        if let r = try? await Account.shared.rpc("pasr_business_community_my_invites", ["p_business": business.id]) {
            for invite in (r as? [Any] ?? []).compactMap(BusinessCommunityView.MyInvite.init) {
                items.append(.init(id: "invite:" + invite.id, kind: .invite,
                                   title: invite.title.isEmpty ? String(localized: "Gezamenlijke actie") : invite.title,
                                   detail: invite.initiator.isEmpty ? String(localized: "Uitnodiging voor een gezamenlijke actie")
                                       : String(format: String(localized: "Uitnodiging van %@"), invite.initiator),
                                   date: invite.startsAt, section: .gezamenlijkeActies, item: invite.campaignID))
            }
        }

        // concepten: stempelkaarten, events en klantenkaarten die nog niet online staan
        for card in business.cards where !card.published {
            items.append(.init(id: "card:" + card.id, kind: .draft, title: card.name,
                               detail: String(localized: "Concept · stempelkaart"), date: nil, section: .stempelkaarten, item: card.id))
        }
        if let events = try? await TKAPI.events(business: business.id) {
            for e in events where e.status == "draft" && e.endsAt > .now {
                items.append(.init(id: "event:" + e.id, kind: .draft, title: e.name,
                                   detail: String(localized: "Concept · event"), date: e.startsAt, section: .tickets, item: e.id))
            }
        }
        if let cards = try? await TKAPI.memberCards(business: business.id) {
            for c in cards {
                if c.status == "draft" {
                    items.append(.init(id: "member:" + c.id, kind: .draft, title: c.name,
                                       detail: String(localized: "Concept · klantenkaart"), date: nil, section: .klantenkaarten, item: c.id))
                }
                // kortingsperiodes die binnen een week aflopen
                for p in c.goals.periods {
                    let end = TKFormat.calendar.date(byAdding: .day, value: 1, to: p.endsOn) ?? p.endsOn
                    guard end > .now, end <= soon else { continue }
                    items.append(.init(id: "period:" + c.id + p.id, kind: .expiring,
                                       title: p.label.isEmpty ? c.name : "\(c.name) · \(p.label)",
                                       detail: String(localized: "Kortingsperiode loopt af"), date: end,
                                       section: .klantenkaarten, item: c.id))
                }
            }
        }

        // actiecodes en kortingsbonnen die binnen een week aflopen
        let parser = ISO8601DateFormatter()
        func ends(_ row: [String: Any]) -> Date? {
            guard let s = row["ends_at"] as? String else { return nil }
            return parser.date(from: s) ?? JSONDates.parse(s)
        }
        if let r = try? await Account.shared.rpc("pasr_business_promo_list", ["p_business": business.id]) {
            for row in r as? [[String: Any]] ?? [] where row["deleted"] as? Bool != true && row["active"] as? Bool == true {
                guard let id = row["id"] as? String, let end = ends(row), end > .now, end <= soon else { continue }
                items.append(.init(id: "code:" + id, kind: .expiring, title: row["title"] as? String ?? String(localized: "Actiecode"),
                                   detail: String(localized: "Actiecode loopt af"), date: end, section: .actiecodes, item: id))
            }
        }
        if let r = try? await Account.shared.rpc("pasr_business_coupon_list", ["p_business": business.id]) {
            for row in r as? [[String: Any]] ?? [] where row["deleted"] as? Bool != true && row["public"] as? Bool == true {
                guard let id = row["id"] as? String, let end = ends(row), end > .now, end <= soon else { continue }
                items.append(.init(id: "coupon:" + id, kind: .expiring, title: row["title"] as? String ?? String(localized: "Kortingscoupon"),
                                   detail: String(localized: "Kortingscoupon loopt af"), date: end, section: .kortingsbonnen, item: id))
            }
        }

        // uitnodigingen eerst, dan wat het eerst afloopt, dan concepten
        func rank(_ k: WidgetSnapshot.TodoItem.Kind) -> Int { k == .invite ? 0 : k == .expiring ? 1 : 2 }
        return items.sorted {
            (rank($0.kind), $0.date ?? .distantFuture, $0.title) < (rank($1.kind), $1.date ?? .distantFuture, $1.title)
        }.prefix(12).map { $0 }
    }
}

/// Waar de app naartoe moet na een link (widget, melding met `app_url`, menubalk). iOS kiest het tabblad, de Mac het
/// onderdeel in de zijbalk.
@MainActor
@Observable
final class AppNavigator {
    static let shared = AppNavigator()
    var request: ZakelijkLink.Target?
}
