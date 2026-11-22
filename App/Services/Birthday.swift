import Foundation
import UserNotifications

/// Verjaardagsvoordeel (sinds 1.0.3). Je verjaardag is optioneel en bestaat alleen uit dag en maand (nooit een
/// jaar). Staat hij erin, dan krijg je op de 1e van je verjaardagsmaand een seintje voor de kaarten waarvan de
/// gids een verjaardagsvoordeel noemt (guide.birthday uit het beheer). Lokaal bewaard; met een Pasr-account ook in
/// je account, zodat je andere apparaten hem kennen (pasr_birthday_get / pasr_birthday_set).
@MainActor
enum Birthday {
    private static let dayKey = "pasr.birthday.day"
    private static let monthKey = "pasr.birthday.month"
    /// Wanneer hij hier het laatst is gewijzigd, en tot wanneer de server hem kent.
    private static let changedKey = "pasr.birthday.changed"
    private static let pushedKey = "pasr.birthday.pushed"

    struct Value: Equatable {
        var day: Int
        var month: Int

        var isValid: Bool {
            guard (1...12).contains(month), day >= 1 else { return false }
            let max = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
            return day <= max
        }

        /// "12 maart"
        var text: String {
            var c = DateComponents()
            c.year = 2000; c.month = month; c.day = day
            guard let date = Calendar(identifier: .gregorian).date(from: c) else { return "\(day)-\(month)" }
            return date.formatted(.dateTime.day().month(.wide))
        }
    }

    static var value: Value? {
        let d = UserDefaults.standard.integer(forKey: dayKey), m = UserDefaults.standard.integer(forKey: monthKey)
        let v = Value(day: d, month: m)
        return v.isValid ? v : nil
    }

    /// Zetten (of met nil wissen) vanuit Instellingen.
    static func set(_ new: Value?, cards: [Card]) {
        store(new)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: changedKey)
        Task {
            await reschedule(cards)
            await syncWithAccount()
        }
    }

    private static func store(_ new: Value?) {
        if let new, new.isValid {
            UserDefaults.standard.set(new.day, forKey: dayKey)
            UserDefaults.standard.set(new.month, forKey: monthKey)
        } else {
            UserDefaults.standard.removeObject(forKey: dayKey)
            UserDefaults.standard.removeObject(forKey: monthKey)
        }
    }

    // MARK: Account

    /// De nieuwste wint: wat hier later is gewijzigd gaat naar de server, anders neemt dit apparaat die van de server.
    static func syncWithAccount() async {
        guard AccountService.shared.isSignedIn else { return }
        let changed = UserDefaults.standard.double(forKey: changedKey)
        let pushed = UserDefaults.standard.double(forKey: pushedKey)
        if changed > pushed {
            let v = value
            let body: [String: Any] = ["p_day": v.map { $0.day as Any } ?? NSNull(), "p_month": v.map { $0.month as Any } ?? NSNull()]
            if (try? await AccountService.shared.rpc("pasr_birthday_set", body: body)) != nil {
                UserDefaults.standard.set(changed, forKey: pushedKey)
            }
            return
        }
        guard let json = try? await AccountService.shared.rpc("pasr_birthday_get", body: [:]) else { return }
        let dict = (json as? [String: Any]) ?? ((json as? [[String: Any]])?.first ?? [:])
        let day = (dict["day"] as? NSNumber)?.intValue, month = (dict["month"] as? NSNumber)?.intValue
        let remote = (day != nil && month != nil) ? Value(day: day!, month: month!) : nil
        let remoteAt = (dict["updated_at"] as? String).flatMap(parse)?.timeIntervalSince1970 ?? 0
        guard remoteAt > changed, remote != value else { return }
        store(remote?.isValid == true ? remote : nil)
        UserDefaults.standard.set(remoteAt, forKey: changedKey)
        UserDefaults.standard.set(remoteAt, forKey: pushedKey)
    }

    private static func parse(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: trimmed) ?? ISO8601DateFormatter().date(from: trimmed)
    }

    // MARK: Herinnering

    /// Kaarten met een verjaardagsvoordeel in de gids (A tot Z, één per winkel).
    static func cardsWithPerk(_ cards: [Card]) -> [(card: Card, perk: String)] {
        var seen: Set<String> = []
        return cards.filter { $0.deletedAt == nil && !$0.isTemporary }.alphabetical().compactMap { card in
            guard let perk = RemoteStores.guide(for: card.templateID, storeName: card.storeName)?.birthday,
                  seen.insert(card.templateID ?? card.storeName.lowercased()).inserted else { return nil }
            return (card, perk)
        }
    }

    /// Plant de herinnering op de 1e van je verjaardagsmaand om 10:00 (en staat die al voorbij, maar is het nog je
    /// verjaardagsmaand en nog niet je verjaardag, dan morgen om 10:00).
    static func reschedule(_ cards: [Card]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["birthday-month"])
        guard Reminders.pushEnabled, let value else { return }
        let list = cardsWithPerk(cards)
        guard !list.isEmpty else { return }
        let calendar = Calendar.current
        let now = Date.now
        let year = calendar.component(.year, from: now)
        // het moment voor dit jaar wordt één keer gekozen en onthouden, zodat opnieuw plannen het niet verschuift
        let key = "pasr.birthday.fire.\(year).\(value.month)"
        var fire: Date?
        let stored = UserDefaults.standard.double(forKey: key)
        if stored > 0 {
            let date = Date(timeIntervalSince1970: stored)
            if date > now { fire = date }
        } else if let first = calendar.date(from: DateComponents(year: year, month: value.month, day: 1, hour: 10)) {
            if first > now {
                fire = first
            } else if calendar.component(.month, from: now) == value.month, calendar.component(.day, from: now) < value.day,
                      let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
                fire = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow)
            }
            if let fire { UserDefaults.standard.set(fire.timeIntervalSince1970, forKey: key) }
        }
        if fire == nil { fire = calendar.date(from: DateComponents(year: year + 1, month: value.month, day: 1, hour: 10)) }
        guard let fire else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Het is bijna je verjaardag")
        if list.count == 1, let first = list.first {
            content.body = "\(first.card.storeName): \(first.perk)"
            content.userInfo = ["cardID": first.card.id.uuidString]
        } else {
            let names = list.prefix(3).map { $0.card.storeName }.joined(separator: ", ")
            let more = list.count > 3 ? String(localized: " en \(list.count - 3) meer") : ""
            content.body = String(localized: "Je hebt verjaardagsvoordeel bij \(names)\(more). Bekijk het bij de kaart onder Details.")
        }
        content.sound = .default
        content.threadIdentifier = "birthday"
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "birthday-month", content: content, trigger: trigger))
    }
}
