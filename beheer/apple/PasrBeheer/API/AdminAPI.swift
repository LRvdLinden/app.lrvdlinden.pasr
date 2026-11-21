import Foundation

/// Fout van de functie `admin` (veld `error`) of van het netwerk, met een Nederlandse uitleg.
struct APIError: Error, LocalizedError, Equatable {
    let code: String
    let status: Int
    var retryAfter: Int? = nil

    var isUnauthorized: Bool { status == 401 || code == "unauthorized" }

    var errorDescription: String? {
        switch code {
        case "network": return "Geen verbinding met de server."
        case "not_configured": return "Het beheer is nog niet ingericht (PASR_ADMIN_USER en PASR_ADMIN_PASSWORD)."
        case "unauthorized": return "Je sessie is verlopen. Log opnieuw in."
        case "invalid_credentials": return "Onjuiste gebruikersnaam of wachtwoord."
        case "locked":
            let minutes = max(1, ((retryAfter ?? 900) + 59) / 60)
            return "Te veel pogingen. Probeer het over \(minutes) minuten opnieuw."
        case "rate_limited": return "Even wachten: te veel verzoeken."
        case "already_confirmed": return "Dit account is al bevestigd."
        case "not_found": return "Dit account bestaat niet meer."
        case "apns_not_configured": return "Pushmeldingen zijn op de server nog niet ingericht (APNs-sleutel)."
        case "not_registered": return "Dit apparaat is nog niet aangemeld voor pushmeldingen."
        case "apns_invalid": return "Apple kent dit apparaat niet (meer). Zet meldingen uit en weer aan."
        case "decode": return "Onverwacht antwoord van de server."
        case "bad_email": return "Dit is geen geldig e-mailadres."
        case "bad_url": return "Vul een geldig https-adres in."
        case "bad_id": return "Dit winkel-id klopt niet (kleine letters, cijfers en streepjes)."
        case "weak_password": return "Kies een wachtwoord van minimaal 10 tekens met letters en cijfers."
        case "exists": return "Dit account bestaat al. Zet \u{201C}wachtwoord vervangen\u{201D} aan."
        case "group_limit": return "Dit account zit al in 2 gedeelde Pasrs."
        case "create_failed", "update_failed", "seed_failed": return "Het review-account kon niet worden gemaakt. Probeer het opnieuw."
        default: return "Er ging iets mis op de server (\(code))."
        }
    }
}

/// `POST {SUPABASE_URL}/functions/v1/admin` met `{action, …}` en na inloggen `Authorization: Bearer <token>`.
struct AdminAPI {
    func send<T: Decodable>(_ action: String, token: String?, params: [String: Any] = [:], as type: T.Type) async throws -> T {
        let data = try await raw(action, token: token, params: params)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(code: "decode", status: 200)
        }
    }

    @discardableResult
    func raw(_ action: String, token: String?, params: [String: Any] = [:]) async throws -> Data {
        guard Config.isConfigured, let url = Config.adminFunction else { throw APIError(code: "not_configured", status: 0) }
        var payload = params
        payload["action"] = action
        var req = URLRequest(url: url, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.publishableKey, forHTTPHeaderField: "apikey")
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw APIError(code: "network", status: 0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw APIError(code: body?.error ?? (status == 401 ? "unauthorized" : "server_error"), status: status, retryAfter: body?.retry_after)
        }
        return data
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let retry_after: Int?
    }
}
