import Foundation
import Observation

/// Waar het Pasr-account woont. Beide waarden zijn openbaar (de publishable key mag alleen wat de database-regels
/// toestaan); zelfde server als de app Pasr. Geen geheimen in de app.
enum AccountConfig {
    static let url = "https://xcfuiszcfgkpbixqzrjb.supabase.co"
    static let publishableKey = "sb_publishable_wFRG_22hV_8FJUX1JcS8SQ_2JHxQlzw"
}

/// Het Pasr-account van de ondernemer of medewerker (e-mail en wachtwoord, zelfde account als in Pasr en op
/// pasr.nl/zakelijk). Gewone HTTPS, geen SDK. De sessie staat alleen op dit apparaat, in de sleutelhanger.
@MainActor
@Observable
final class Account {
    static let shared = Account()

    struct Session: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
        var email: String
        var firstName: String?
    }

    enum SignUpResult { case signedIn, checkInbox }

    private(set) var session: Session?
    var isSignedIn: Bool { session != nil }

    private init() {
        session = Keychain.load(Session.self)
    }

    // MARK: Inloggen

    func signIn(email: String, password: String) async throws {
        let json = try await request("auth/v1/token?grant_type=password",
                                     body: ["email": Self.clean(email), "password": password])
        try store(json)
    }

    func signUp(firstName: String, email: String, password: String, honeypot: String, fillMilliseconds: Int) async throws -> SignUpResult {
        var data: [String: Any] = ["first_name": Self.cleanName(firstName), "fill_ms": fillMilliseconds, "app": "zakelijk-ios"]
        if !honeypot.isEmpty { data["hp"] = honeypot }
        let body: [String: Any] = ["email": Self.clean(email), "password": password, "data": data]
        let json = try await request("auth/v1/signup?redirect_to=https%3A%2F%2Fpasr.nl%2Fbevestigen%2F", body: body)
        if json["access_token"] != nil {
            try store(json)
            return .signedIn
        }
        return .checkInbox
    }

    /// Lukt altijd (de server zegt nooit of een adres een account heeft).
    func sendPasswordReset(email: String) async throws {
        _ = try await request("auth/v1/recover?redirect_to=https%3A%2F%2Fpasr.nl%2Fbevestigen%2F", body: ["email": Self.clean(email)])
    }

    func resendConfirmation(email: String) async throws {
        _ = try await request("auth/v1/resend", body: ["type": "signup", "email": Self.clean(email)])
    }

    func signOut() async {
        if let token = session?.accessToken {
            _ = try? await request("auth/v1/logout?scope=local", body: [:], token: token)
        }
        clear()
    }

    /// Verwijdert het Pasr-account (ook je zaak als je eigenaar bent). Zelfde functie als in Pasr.
    func deleteAccount() async throws {
        _ = try await rpc("pasr_delete_account", [:])
        clear()
    }

    func clear() {
        session = nil
        Keychain.delete()
    }

    // MARK: Database

    /// Roept een databasefunctie aan (POST /rest/v1/rpc/<naam>) als de ingelogde gebruiker.
    func rpc(_ name: String, _ body: [String: Any]) async throws -> Any {
        let token = try await validAccessToken()
        return try await requestAny("rest/v1/rpc/\(name)", body: body, token: token)
    }

    /// Roept een Edge Function aan (POST /functions/v1/<naam>) als de ingelogde gebruiker.
    func function(_ name: String, _ body: [String: Any]) async throws -> Any {
        let token = try await validAccessToken()
        return try await requestAny("functions/v1/\(name)", body: body, token: token)
    }

    private func validAccessToken() async throws -> String {
        guard let current = session else { throw APIError(String(localized: "Je bent niet ingelogd.")) }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        do {
            let json = try await request("auth/v1/token?grant_type=refresh_token", body: ["refresh_token": current.refreshToken])
            try store(json)
            return session?.accessToken ?? current.accessToken
        } catch let error as APIError where error.status == 400 || error.status == 401 {
            clear()
            throw APIError(String(localized: "Je bent uitgelogd. Log opnieuw in."))
        }
    }

    // MARK: HTTP

    private func request(_ path: String, body: [String: Any], token: String? = nil) async throws -> [String: Any] {
        (try await requestAny(path, body: body, token: token) as? [String: Any]) ?? [:]
    }

    private func requestAny(_ path: String, body: [String: Any], token: String? = nil) async throws -> Any {
        guard let url = URL(string: "\(AccountConfig.url)/\(path)") else { throw APIError(String(localized: "Er ging iets mis. Probeer het opnieuw.")) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AccountConfig.publishableKey, forHTTPHeaderField: "apikey")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(String(localized: "Geen verbinding. Controleer je internet en probeer het opnieuw."))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json: Any = data.isEmpty ? [String: Any]() : ((try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) ?? [String: Any]())
        guard (200..<300).contains(status) else {
            let d = json as? [String: Any] ?? [:]
            let code = (d["error_code"] ?? d["code"] ?? d["error"]) as? String ?? ""
            let message = (d["msg"] ?? d["message"] ?? d["error_description"]) as? String ?? ""
            let hint = d["hint"] as? String ?? ""
            let details = d["details"] as? String ?? ""
            throw APIError.from(status: status, code: code, message: message, hint: hint, details: details)
        }
        return json
    }

    private func store(_ json: [String: Any]) throws {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any], let id = user["id"] as? String else {
            throw APIError(String(localized: "Er ging iets mis. Probeer het opnieuw."))
        }
        let expires = (json["expires_in"] as? Double) ?? 3600
        let meta = user["user_metadata"] as? [String: Any]
        let new = Session(accessToken: access, refreshToken: refresh, expiresAt: .now.addingTimeInterval(expires),
                          userID: id, email: user["email"] as? String ?? session?.email ?? "",
                          firstName: meta?["first_name"] as? String ?? session?.firstName)
        session = new
        Keychain.save(new)
    }

    static func clean(_ email: String) -> String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    static func cleanName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[<>]", with: "", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return String(cleaned.prefix(40))
    }
}

/// Een fout met een nette tekst voor in beeld.
struct APIError: LocalizedError {
    let message: String
    var status = 0
    var errorDescription: String? { message }

    init(_ message: String, status: Int = 0) {
        self.message = message
        self.status = status
    }

    /// Nette tekst bij wat de server zegt. De databasefuncties van Pasr Zakelijk sturen een vaste code in `hint`
    /// (cooldown, too_many, not_allowed, …) en een Nederlandse zin in `message`; de app vertaalt op de code.
    static func from(status: Int, code: String, message: String, hint: String = "", details: String = "") -> APIError {
        if let text = hintText(hint, details: details, message: message) { return APIError(text, status: status) }
        let s = code + " " + message
        func has(_ k: String) -> Bool { s.localizedCaseInsensitiveContains(k) }
        let text: String
        if has("invalid_credentials") || (status == 400 && code == "invalid_grant") {
            text = String(localized: "E-mailadres of wachtwoord klopt niet.")
        } else if has("email_not_confirmed") || has("not_confirmed") {
            text = String(localized: "Bevestig eerst je e-mailadres. Kijk in je inbox (en bij ongewenste mail).")
        } else if has("weak_password") {
            text = String(localized: "Kies een wachtwoord van minstens 8 tekens.")
        } else if has("user_already_exists") || has("email_exists") {
            text = String(localized: "Er is al een account met dit e-mailadres. Log in of vraag een nieuw wachtwoord aan.")
        } else if has("email_address_invalid") || has("validation_failed") {
            text = String(localized: "Dit e-mailadres klopt niet.")
        } else if status == 429 || has("rate_limit") {
            text = String(localized: "Te veel pogingen. Wacht een paar minuten en probeer het opnieuw.")
        } else if let mapped = hintText(message.trimmingCharacters(in: .whitespaces), details: details, message: "") {
            text = mapped   // oudere functies: de code staat in message ("not_found", "bad_name", …)
        } else if let k = ["invite_required", "already_participant", "invite_not_found", "invite_expired", "not_owner"].first(where: has),
                  let mapped = hintText(k, details: details, message: "") {
            text = mapped   // gezamenlijke acties: code ergens in de melding
        } else if code == "P0002" {
            text = String(localized: "Deze code is niet bekend. Laat de klant de kaart opnieuw tonen of typ de code over.")
        } else if code == "28000" {
            text = String(localized: "Je bent uitgelogd. Log opnieuw in.")
        } else if message.count > 12, message.contains(" "), message.range(of: "[a-z]+_[a-z]+", options: .regularExpression) == nil {
            text = message
        } else {
            text = String(localized: "Er ging iets mis. Probeer het opnieuw.")
        }
        return APIError(text, status: status)
    }

    private static func hintText(_ hint: String, details: String, message: String) -> String? {
        switch hint {
        case "cooldown":
            if let seconds = Int(details.trimmingCharacters(in: .whitespaces)), seconds > 0 {
                let minutes = max(1, Int((Double(seconds) / 60).rounded(.up)))
                return String(format: String(localized: "Deze klant kreeg net al een stempel. Probeer het over %lld min opnieuw."), minutes)
            }
            return String(localized: "Deze klant kreeg net al een stempel. Probeer het straks opnieuw.")
        case "too_many", "bad_amount":
            return String(localized: "Zoveel stempels tegelijk mag niet. Pas het maximum aan in Instellingen.")
        case "too_soon":
            return String(localized: "Net al gescand. Wacht een paar seconden.")
        case "not_approved":
            return String(localized: "Je zaak is nog niet goedgekeurd. Stempels zetten kan pas daarna.")
        case "not_allowed", "not_owner":
            return String(localized: "Dit mag je niet (meer) bij deze zaak. Vraag de eigenaar.")
        case "not_found":
            return String(localized: "Deze code is niet bekend. Laat de klant de kaart opnieuw tonen of typ de code over.")
        case "other_business":
            return String(localized: "Deze kaart hoort bij een andere zaak.")
        case "not_enough":
            return String(localized: "De kaart is nog niet vol. Inwisselen kan pas bij een volle kaart.")
        case "undo_expired":
            return String(localized: "Ongedaan maken kan alleen binnen 2 minuten.")
        case "undo_not_latest":
            return String(localized: "Alleen de laatste actie bij deze klant kan ongedaan worden gemaakt.")
        case "invite_invalid":
            return String(localized: "Deze uitnodiging bestaat niet (meer). Vraag de eigenaar om een nieuwe.")
        case "invite_required":
            return String(localized: "Meedoen aan deze gezamenlijke actie kan alleen op uitnodiging van de organisator.")
        case "already_participant":
            return String(localized: "Deze zaak doet al mee aan deze gezamenlijke actie.")
        case "invite_not_found":
            return String(localized: "Deze uitnodiging bestaat niet (meer). Vraag de organisator om een nieuwe.")
        case "invite_expired":
            return String(localized: "Deze uitnodiging is verlopen. Vraag de organisator om een nieuwe.")
        case "invite_own":
            return String(localized: "Dit is een uitnodiging voor je eigen zaak.")
        case "staff_limit":
            return String(localized: "Je hebt al 25 medewerkers. Trek er eerst één in.")
        case "bad_settings":
            return String(localized: "Deze instellingen kloppen niet.")
        case "bad_name":
            return String(localized: "Vul een naam in.")
        case "bad_email":
            return String(localized: "Dit e-mailadres klopt niet.")
        case "bad_reward":
            return String(localized: "Vul de beloning in.")
        case "bad_logo":
            return String(localized: "Dit logo is te groot of geen afbeelding. Kies een kleinere afbeelding.")
        case "card_limit":
            return String(localized: "Je hebt al 5 kaarten. Verwijder er eerst één.")
        case "blocked":
            return String(localized: "Deze zaak is geblokkeerd. Neem contact op met Pasr.")
        case "not_signed_in", "not signed in":
            return String(localized: "Je bent uitgelogd. Log opnieuw in.")
        case "rate_limited":
            return String(localized: "Te veel pogingen. Wacht een paar minuten en probeer het opnieuw.")
        default:
            return nil
        }
    }
}
