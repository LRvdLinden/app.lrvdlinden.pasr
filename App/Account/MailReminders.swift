import Foundation

/// Herinneringen per e-mail (sinds 1.0.2): vervaldatums, verlengingen en tegoed, gestuurd door de server vanaf
/// support@pasr.nl. Kan alleen met een Pasr-account: de server kent je kaarten alleen als ze in je account staan
/// (versleuteld) en mailt naar het adres van je account. De keuze staat op de server (pasr_mail_prefs).
@MainActor
enum MailReminders {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Stuurt de keuzes van dit apparaat naar het account. `enabled` false = geen mails meer.
    static func save(enabled: Bool) async throws {
        guard AccountService.shared.isSignedIn else {
            throw Failure(message: String(localized: "Log in met je Pasr-account om herinneringen per e-mail te krijgen."))
        }
        let body: [String: Any] = [
            "p_enabled": enabled,
            "p_expiry": Reminders.vouchersEnabled,
            "p_balance": Reminders.balanceEnabled,
            "p_interval": Reminders.balanceInterval.rawValue,
            "p_tz": TimeZone.current.identifier,
        ]
        do {
            _ = try await AccountService.shared.rpc("pasr_mail_prefs_set", body: body)
        } catch {
            throw Failure(message: String(localized: "E-mailherinneringen konden niet worden opgeslagen. Probeer het later opnieuw."))
        }
    }

    /// Bij het openen van de instellingen: staan de mails aan in het account (bijvoorbeeld ingesteld op een ander
    /// apparaat), dan laat dit apparaat dat ook zien. Pushmeldingen op dit apparaat blijven zoals ze waren.
    static func refreshChannel() async {
        guard AccountService.shared.isSignedIn,
              let json = try? await AccountService.shared.rpc("pasr_mail_prefs_get", body: [:]) as? [String: Any] else { return }
        let enabled = json["enabled"] as? Bool ?? false
        let current = Reminders.channel
        let next: Reminders.Channel = enabled ? (current == .mail ? .mail : .both) : .push
        if next != current { UserDefaults.standard.set(next.rawValue, forKey: Reminders.channelKey) }
    }

    /// Na een wijziging van de schakelaars (vervaldatums, tegoed, ritme): bijwerken als de mails aanstaan.
    static func syncIfMailing() async {
        guard AccountService.shared.isSignedIn, Reminders.channel != .push else { return }
        try? await save(enabled: true)
    }
}
