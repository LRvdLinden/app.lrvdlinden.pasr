import Foundation

/// "Nieuws over mijn kaarten" (sinds 1.0.3): wie dit aanzet, krijgt af en toe een pushbericht van Pasr over een
/// winkel waarvan hij een kaart heeft (bijvoorbeeld een nieuwe actie). De app meldt daarvoor welke winkels
/// (template-ids uit de catalogus) er in Pasr staan: alleen die ids, nooit kaartnummers of andere gegevens.
/// Uitzetten wist de lijst op de server. Met een Pasr-account via pasr_push_stores (het token staat dan al in
/// pasr_user_push), zonder account via pasr_news_register / pasr_news_unregister met het token van dit apparaat.
@MainActor
enum StorePush {
    static let key = "pasr.push.cardNews"
    private static let idsKey = "pasr.push.cardNews.ids"
    private static let sentKey = "pasr.push.cardNews.sent"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Unieke winkel-ids van je eigen kaarten (geen tijdelijke), A tot Z, hoogstens 300.
    static func storeIDs(_ cards: [Card]) -> [String] {
        let ids = cards.filter { $0.deletedAt == nil && !$0.isTemporary }
            .compactMap { $0.templateID?.lowercased() }
            .filter { $0.range(of: "^[a-z0-9-]{2,40}$", options: .regularExpression) != nil }
        return Array(Set(ids)).sorted().prefix(300).map { $0 }
    }

    /// Kaarten veranderd (WidgetSync): de lijst onthouden en, als het aanstaat, bijwerken op de server.
    static func cardsChanged(_ cards: [Card]) {
        let ids = storeIDs(cards)
        guard ids != (UserDefaults.standard.stringArray(forKey: idsKey) ?? []) else { return }
        UserDefaults.standard.set(ids, forKey: idsKey)
        guard isEnabled else { return }
        Task { await syncIfEnabled() }
    }

    /// Aan- of uitzetten vanuit Instellingen. Geeft een foutmelding terug als het niet lukte.
    static func setEnabled(_ on: Bool, cards: [Card]) async -> String? {
        UserDefaults.standard.set(storeIDs(cards), forKey: idsKey)
        if on {
            guard await UserPush.enable() else {
                return String(localized: "Sta meldingen voor Pasr toe in de Instellingen van je iPhone.")
            }
            UserDefaults.standard.set(true, forKey: key)
            if AccountService.shared.isSignedIn {
                await UserPush.sync()   // registreert het apparaat en stuurt daarna de winkels (zie UserPush.sync)
            }
            if !UserPush.hasToken { return nil }   // het token komt zo; dan gaat het via didRegister vanzelf
            return await send(force: true) ? nil : String(localized: "Aanmelden lukte nu niet. Pasr probeert het later opnieuw.")
        }
        UserDefaults.standard.set(false, forKey: key)
        _ = await send(force: true)
        return nil
    }

    /// Stuurt de lijst als die anders is dan de vorige keer (of met `force`). Ook "uit" wordt één keer gestuurd.
    static func syncIfEnabled(force: Bool = false) async {
        guard isEnabled || UserDefaults.standard.string(forKey: sentKey)?.hasPrefix("1|") == true else { return }
        _ = await send(force: force)
    }

    @discardableResult
    private static func send(force: Bool) async -> Bool {
        let account = AccountService.shared
        let on = isEnabled
        let ids = on ? (UserDefaults.standard.stringArray(forKey: idsKey) ?? []) : []
        let user = account.session?.userID ?? "-"
        let token = UserPush.token ?? ""
        let fingerprint = "\(on ? 1 : 0)|\(user)|\(UserPush.deviceID)|\(token.suffix(8))|" + ids.joined(separator: ",")
        if !force, UserDefaults.standard.string(forKey: sentKey) == fingerprint { return true }
        do {
            if account.isSignedIn {
                _ = try await account.rpc("pasr_push_stores", body: [
                    "p_device": UserPush.deviceID, "p_enabled": on, "p_stores": ids,
                ])
            } else if on {
                guard !token.isEmpty else { return false }   // het token komt nog (didRegister stuurt dan opnieuw)
                _ = try await account.publicRPC("pasr_news_register", body: [
                    "p_device": UserPush.deviceID, "p_token": token, "p_sandbox": PushEnvironment.isSandbox, "p_stores": ids,
                ])
            } else {
                _ = try await account.publicRPC("pasr_news_unregister", body: ["p_device": UserPush.deviceID])
            }
            UserDefaults.standard.set(fingerprint, forKey: sentKey)
            return true
        } catch {
            return false
        }
    }
}
