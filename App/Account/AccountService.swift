import Foundation
import Security
import Observation

/// Where the Pasr account lives. Both values are public (the publishable key only allows what the database
/// rules allow). Empty = this build has no accounts: the app then works as before, with iCloud only.
enum AccountConfig {
    static let url = "https://xcfuiszcfgkpbixqzrjb.supabase.co"              // e.g. "https://abcd1234.supabase.co"
    static let publishableKey = "sb_publishable_wFRG_22hV_8FJUX1JcS8SQ_2JHxQlzw"   // "sb_publishable_…" or the anon key "eyJ…"

    static var isConfigured: Bool { !url.isEmpty && !publishableKey.isEmpty }
}

/// The optional Pasr account: e-mail and password, with a confirmation mail and "forgot password". Talks to the
/// account server with plain HTTPS (no SDK). The session stays on this device only, in the keychain.
@MainActor
@Observable
final class AccountService {
    static let shared = AccountService()

    struct Session: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
        var email: String
        var firstName: String?
    }

    enum SignUpResult { case signedIn, checkInbox }

    struct AccountError: LocalizedError {
        let message: String
        var status = 0
        var errorDescription: String? { message }
    }

    private(set) var session: Session?
    var isSignedIn: Bool { session != nil }

    private init() {
        session = Keychain.load()
    }

    // MARK: Account

    /// `honeypot` is the hidden field (people leave it empty), `fillMilliseconds` how long the form was open.
    func signUp(firstName: String, email: String, password: String, honeypot: String, fillMilliseconds: Int) async throws -> SignUpResult {
        var data: [String: Any] = ["first_name": Self.cleanName(firstName), "fill_ms": fillMilliseconds, "app": "ios"]
        if !honeypot.isEmpty { data["hp"] = honeypot }
        if let country = Self.deviceCountry { data["country"] = country }
        let body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password, "data": data]
        let json = try await request("auth/v1/signup?redirect_to=https%3A%2F%2Fpasr.nl%2Fbevestigen%2F", body: body)
        if json["access_token"] != nil {
            try store(json)
            return .signedIn
        }
        return .checkInbox
    }

    func signIn(email: String, password: String) async throws {
        let json = try await request("auth/v1/token?grant_type=password",
                                     body: ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password])
        try store(json)
    }

    /// Always "succeeds" (the server never says whether an address has an account).
    func sendPasswordReset(email: String) async throws {
        _ = try await request("auth/v1/recover?redirect_to=https%3A%2F%2Fpasr.nl%2Fbevestigen%2F",
                              body: ["email": email.trimmingCharacters(in: .whitespaces).lowercased()])
    }

    func resendConfirmation(email: String) async throws {
        _ = try await request("auth/v1/resend", body: ["type": "signup", "email": email.trimmingCharacters(in: .whitespaces).lowercased()])
    }

    /// Signs out on this device only. Cards stay on the device.
    func signOut() async {
        if let token = session?.accessToken {
            _ = try? await request("auth/v1/logout?scope=local", body: [:], token: token)
        }
        clear()
    }

    /// Deletes the account and the cards stored in it. The cards on this device stay.
    func deleteAccount() async throws {
        _ = try await rpc("pasr_delete_account", body: [:])
        clear()
    }

    func clear() {
        if let id = session?.userID { CardSync.forget(userID: id) }
        session = nil
        GroupService.shared.reset()
        Keychain.delete()
    }

    // MARK: Calls with the session

    /// Calls a database function (POST /rest/v1/rpc/<name>) as the signed-in user.
    func rpc(_ name: String, body: [String: Any]) async throws -> Any {
        let token = try await validAccessToken()
        return try await requestAny("rest/v1/rpc/\(name)", body: body, token: token)
    }

    /// Calls an edge function (POST /functions/v1/<name>) as the signed-in user.
    func function(_ name: String, body: [String: Any]) async throws -> [String: Any] {
        let token = try await validAccessToken()
        return (try await requestAny("functions/v1/\(name)", body: body, token: token) as? [String: Any]) ?? [:]
    }

    private func validAccessToken() async throws -> String {
        guard let current = session else { throw AccountError(message: String(localized: "Je bent niet ingelogd.")) }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        do {
            let json = try await request("auth/v1/token?grant_type=refresh_token", body: ["refresh_token": current.refreshToken])
            try store(json)
            return session?.accessToken ?? current.accessToken
        } catch let error as AccountError where error.status == 400 || error.status == 401 {
            clear()   // the session was ended elsewhere (password changed, account removed)
            throw AccountError(message: String(localized: "Je bent uitgelogd. Log opnieuw in."))
        }
    }

    // MARK: HTTP

    struct HTTPFailure: Error {
        let status: Int
        let code: String
        let message: String
    }

    private func request(_ path: String, body: [String: Any], token: String? = nil) async throws -> [String: Any] {
        (try await requestAny(path, body: body, token: token) as? [String: Any]) ?? [:]
    }

    private func requestAny(_ path: String, body: [String: Any], token: String? = nil) async throws -> Any {
        guard AccountConfig.isConfigured, let url = URL(string: "\(AccountConfig.url)/\(path)") else {
            throw AccountError(message: String(localized: "Accounts zijn in deze versie nog niet beschikbaar."))
        }
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
            throw AccountError(message: String(localized: "Geen verbinding. Controleer je internet en probeer het opnieuw."))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? [:] : ((try? JSONSerialization.jsonObject(with: data)) ?? [:])
        guard (200..<300).contains(status) else {
            let dict = json as? [String: Any] ?? [:]
            let code = (dict["error_code"] ?? dict["code"] ?? dict["error"]) as? String ?? ""
            let message = (dict["msg"] ?? dict["message"] ?? dict["error_description"]) as? String ?? ""
            throw Self.friendly(HTTPFailure(status: status, code: code, message: message))
        }
        return json
    }

    private func store(_ json: [String: Any]) throws {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any], let id = user["id"] as? String else {
            throw AccountError(message: String(localized: "Er ging iets mis. Probeer het opnieuw."))
        }
        let expires = (json["expires_in"] as? Double) ?? 3600
        let meta = user["user_metadata"] as? [String: Any]
        let new = Session(accessToken: access, refreshToken: refresh, expiresAt: .now.addingTimeInterval(expires),
                          userID: id, email: user["email"] as? String ?? session?.email ?? "",
                          firstName: meta?["first_name"] as? String ?? session?.firstName)
        session = new
        Keychain.save(new)
    }

    /// Dutch messages for what the server says.
    private static func friendly(_ f: HTTPFailure) -> Error {
        let text: String
        switch (f.status, f.code) {
        case (_, "invalid_credentials"), (400, "invalid_grant"):
            text = String(localized: "E-mailadres of wachtwoord klopt niet.")
        case (_, "email_not_confirmed"):
            text = String(localized: "Bevestig eerst je e-mailadres. Kijk in je inbox (en bij ongewenste mail).")
        case (_, "weak_password"):
            text = String(localized: "Kies een wachtwoord van minstens 8 tekens.")
        case (_, "user_already_exists"), (_, "email_exists"):
            text = String(localized: "Er is al een account met dit e-mailadres. Log in of vraag een nieuw wachtwoord aan.")
        case (_, "email_address_invalid"), (_, "validation_failed"):
            text = String(localized: "Dit e-mailadres klopt niet.")
        case (429, _), (_, "over_email_send_rate_limit"), (_, "over_request_rate_limit"):
            text = String(localized: "Te veel pogingen. Wacht een paar minuten en probeer het opnieuw.")
        default:
            if let group = groupMessage(f.code + " " + f.message) {
                text = group
            } else if f.message.contains("permanent email") {
                text = String(localized: "Gebruik een vast e-mailadres; tijdelijke adressen werken niet.")
            } else {
                text = String(localized: "Er ging iets mis. Probeer het opnieuw.")
            }
        }
        return AccountError(message: text, status: f.status)
    }

    /// Meldingen van de gedeelde Pasr (database en functie group-invite).
    private static func groupMessage(_ s: String) -> String? {
        if s.contains("group_limit") { return String(localized: "Je zit al in 2 gedeelde Pasrs. Verlaat er eerst één.") }
        if s.contains("member_limit") { return String(localized: "Een gedeelde Pasr heeft maximaal 6 leden. Openstaande uitnodigingen tellen mee.") }
        if s.contains("already_member") { return String(localized: "Deze persoon zit al in deze gedeelde Pasr.") }
        if s.contains("bad_email") { return String(localized: "Dit e-mailadres klopt niet.") }
        if s.contains("rate_limited") { return String(localized: "Je hebt vandaag al veel uitnodigingen gestuurd. Probeer het morgen opnieuw.") }
        if s.contains("invite_not_found") { return String(localized: "Deze uitnodiging bestaat niet meer.") }
        if s.contains("not_confirmed") { return String(localized: "Bevestig eerst je e-mailadres. Daarna kun je de uitnodiging accepteren.") }
        if s.contains("not a member") || s.contains("not_a_member") { return String(localized: "Je bent geen lid meer van deze gedeelde Pasr.") }
        return nil
    }

    /// Regio-instelling van het apparaat ("NL"), alleen voor de landentelling in het beheer. Geen locatie.
    static var deviceCountry: String? {
        guard let code = Locale.current.region?.identifier, code.count == 2, code.allSatisfy(\.isLetter) else { return nil }
        return code.uppercased()
    }

    static func cleanName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[<>]", with: "", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return String(cleaned.prefix(40))
    }
}

/// The session in the keychain, on this device only (refresh tokens are single use, so never synced).
private enum Keychain {
    static let service = "nl.lrvdlinden.pasr.account"

    static func save(_ session: AccountService.Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        delete()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "session", kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> AccountService.Session? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "session", kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AccountService.Session.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "session"]
        SecItemDelete(query as CFDictionary)
    }
}
