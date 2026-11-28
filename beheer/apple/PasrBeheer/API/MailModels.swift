import Foundation

// MARK: - Modellen van de mail_*-acties (zie het contract Pasr beheer › Mail). Geen e-mailadressen in logs.

enum MailBrand: String, CaseIterable, Identifiable, Codable {
    case pasr, zakelijk
    var id: String { rawValue }
    var title: String { self == .pasr ? "Pasr" : "Pasr Zakelijk" }
}

/// Tijdelijke tekst bij fouten van de mail-acties (plain String, zoals APIError).
extension APIError {
    var mailDescription: String {
        switch code {
        case "bad_subject": return String(localized: "Vul een onderwerp in.")
        case "bad_body": return String(localized: "Schrijf een bericht.")
        case "bad_address": return String(localized: "Een of meer e-mailadressen kloppen niet.")
        case "too_many": return String(localized: "Te veel ontvangers (maximaal 200 per keer).")
        case "too_large": return String(localized: "De bijlagen zijn samen te groot (maximaal 20 MB).")
        case "rate_limited": return String(localized: "Even wachten: er zijn te veel mails verstuurd. Probeer het zo opnieuw.")
        case "smtp_not_configured": return String(localized: "E-mail is op de server nog niet ingericht (PASR_SMTP_*).")
        case "not_found": return String(localized: "Niet gevonden.")
        default: return errorDescription ?? code
        }
    }
}

extension Error {
    /// Leesbare tekst voor een fout van een mail-actie.
    var mailText: String {
        if let e = self as? APIError { return e.mailDescription }
        return localizedDescription
    }
}

struct MailCounts: Decodable, Equatable {
    var new: Int? = nil
    var open: Int? = nil
    var pending: Int? = nil
    var closed: Int? = nil
    var unread: Int? = nil

    func count(for filter: String) -> Int? {
        switch filter {
        case "active": return (new ?? 0) + (open ?? 0) + (pending ?? 0)
        case "all": return (new ?? 0) + (open ?? 0) + (pending ?? 0) + (closed ?? 0)
        case "new": return new
        case "open": return open
        case "pending": return pending
        case "closed": return closed
        default: return nil
        }
    }
}

/// `mail_status`
struct MailStatus: Decodable {
    struct Brand: Decodable { let from: String? }
    struct Brands: Decodable { let pasr: Brand?; let zakelijk: Brand? }
    struct Sync: Decodable {
        let last_run: String?
        let last_error: String?
        let fetched: Int?
        let imported: Int?
    }
    let smtp: Bool?
    let imap: Bool?
    let brands: Brands?
    let sync: Sync?
    let counts: MailCounts?

    func from(_ brand: MailBrand) -> String? {
        brand == .pasr ? brands?.pasr?.from : brands?.zakelijk?.from
    }
}

/// Rij in de ticketlijst en het ticket zelf (`mail_thread_list`, `mail_thread_get`).
struct MailThread: Decodable, Identifiable, Hashable {
    let number: Int
    let subject: String?
    let status: String?
    let brand: String?
    let priority: String?
    let contact_name: String?
    let contact_email: String?
    let created_at: String?
    let last_message_at: String?
    let unread: Bool?
    let preview: String?
    // alleen in de lijst (`box`: inbox of sent)
    let last_direction: String?
    let to_preview: MailFlexText?
    let to_count: Int?
    let cc_count: Int?
    let bcc_count: Int?
    let attachments: MailFlexCount?
    let sent_at: String?
    var id: Int { number }
}

/// Tekst of lijst van teksten (de server mag `to_preview` als string of als lijst sturen).
struct MailFlexText: Decodable, Hashable {
    let text: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s }
        else if let a = try? c.decode([String].self) { text = a.joined(separator: ", ") }
        else { text = "" }
    }
}

/// Aantal bijlagen: een getal of een lijst.
struct MailFlexCount: Decodable, Hashable {
    let count: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { count = n }
        else if let a = try? c.decode([MailAttachment].self) { count = a.count }
        else { count = 0 }
    }
}

struct MailThreadList: Decodable {
    let total: Int?
    let page: Int?
    let items: [MailThread]
    let counts: MailCounts?
}

struct MailAttachment: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String?
    let size: Int?
}

struct MailMessage: Decodable, Identifiable {
    let id: String
    let direction: String   // in, out, note
    let from: String?
    let to: [String]?
    let cc: [String]?
    let bcc_count: Int?
    let subject: String?
    let body_html: String?
    let body_text: String?
    let attachments: [MailAttachment]?
    let created_at: String?
    let error: String?
}

struct MailThreadDetail: Decodable {
    let thread: MailThread
    let messages: [MailMessage]
}

struct MailReplyResponse: Decodable {
    let ok: Bool?
    let status: String?
    let email_sent: Bool?
    let message_id: String?
}

struct MailComposeResponse: Decodable {
    let ok: Bool?
    let sent: Int?
    let failed: Int?
    let number: Int?
}

struct MailPollResponse: Decodable {
    let ok: Bool?
    let skipped: String?
    let fetched: Int?
    let imported: Int?
    let new_threads: Int?
    let replies: Int?
    let ignored: Int?
    let rejected: Int?
    let error: String?
}

struct MailPreviewResponse: Decodable {
    let html: String?
    let text: String?
}

struct MailAttachmentData: Decodable {
    let name: String?
    let type: String?
    let data_b64: String?
}

struct MailAudienceCount: Decodable {
    let count: Int
}

struct MailCampaignSendResponse: Decodable {
    let ok: Bool?
    let campaign_id: Int?
    let recipients: Int?
}

struct MailCampaign: Decodable, Identifiable {
    let id: Int
    let brand: String?
    let audience: String?
    let subject: String?
    let status: String?
    let recipients: Int?
    let sent: Int?
    let failed: Int?
    let created_at: String?
}

/// `mail_campaign_list` geeft een lijst; sommige versies verpakken die in een object.
struct MailCampaignList: Decodable {
    let items: [MailCampaign]

    private struct Wrapper: Decodable {
        let items: [MailCampaign]?
        let campaigns: [MailCampaign]?
    }

    init(from decoder: Decoder) throws {
        if let list = try? [MailCampaign](from: decoder) {
            items = list
        } else {
            let w = try Wrapper(from: decoder)
            items = w.items ?? w.campaigns ?? []
        }
    }
}

// MARK: - Adressen

/// Adressen uit een geplakte tekst (komma, puntkomma, spatie of regel), "Naam <adres>" en mailto: worden ondersteund.
struct MailAddressList: Equatable {
    var valid: [String] = []
    var invalid: [String] = []
    var duplicates = 0

    static func parse(_ raw: String) -> MailAddressList {
        var out = MailAddressList()
        var seen = Set<String>()
        let pieces = raw.components(separatedBy: CharacterSet(charactersIn: ",;\n\r\t"))
        for piece in pieces {
            var tokens: [String] = []
            if let r = piece.range(of: #"<([^<>\s]+)>"#, options: .regularExpression) {
                tokens = [String(piece[r]).trimmingCharacters(in: CharacterSet(charactersIn: "<> "))]
            } else {
                tokens = piece.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            }
            for var t in tokens {
                t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'()[]<>.,;: "))
                if t.lowercased().hasPrefix("mailto:") { t = String(t.dropFirst(7)) }
                if t.isEmpty { continue }
                let key = t.lowercased()
                if !isValid(t) {
                    if !out.invalid.contains(t) { out.invalid.append(t) }
                } else if seen.contains(key) {
                    out.duplicates += 1
                } else {
                    seen.insert(key)
                    out.valid.append(t)
                }
            }
        }
        return out
    }

    static func isValid(_ s: String) -> Bool {
        guard s.count <= 254, !s.contains(" ") else { return false }
        return s.range(of: #"^[A-Za-z0-9._%+\-']+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }
}

// MARK: - Concepten (alleen in het geheugen, nooit op schijf; BCC-lijsten worden niet bewaard)

struct MailDraftAttachment: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let type: String
    let data: Data

    var json: [String: Any] { ["name": name, "type": type, "data_b64": data.base64EncodedString()] }
}

enum MailLimits {
    static let attachmentBytes = 20 * 1024 * 1024
    static let recipients = 200
}

@MainActor
final class ComposeDraft: ObservableObject {
    @Published var to = ""
    @Published var cc = ""
    @Published var bcc = ""
    @Published var subject = ""
    @Published var body = ""
    @Published var brand: MailBrand = .pasr
    @Published var attachments: [MailDraftAttachment] = []
    @Published var testAddress = ""
    /// Handtekening Team Pasr / Team Pasr Zakelijk onder de mail (standaard aan)
    @Published var signature = true

    var toList: MailAddressList { MailAddressList.parse(to) }
    var ccList: MailAddressList { MailAddressList.parse(cc) }
    var bccList: MailAddressList { MailAddressList.parse(bcc) }
    var attachmentBytes: Int { attachments.reduce(0) { $0 + $1.data.count } }

    func clear() {
        to = ""; cc = ""; bcc = ""; subject = ""; body = ""; attachments = []
    }
}

@MainActor
final class NewsletterDraft: ObservableObject {
    @Published var audience = "users"
    @Published var brand: MailBrand = .pasr
    @Published var subject = ""
    @Published var body = ""
    @Published var testAddress = ""
    @Published var signature = true
    /// Hetzelfde id bij een nieuwe poging, zodat de server niet dubbel verstuurt (idempotent op request_id).
    @Published var requestID = UUID().uuidString.lowercased()

    func clear() {
        subject = ""; body = ""; requestID = UUID().uuidString.lowercased()
    }
}

@MainActor
final class MailDrafts {
    static let shared = MailDrafts()
    let compose = ComposeDraft()
    let newsletter = NewsletterDraft()

    func reset() {
        compose.clear(); compose.testAddress = ""
        newsletter.clear(); newsletter.testAddress = ""
    }
}

enum MailLabels {
    static let filters: [(key: String, label: String)] = [
        ("active", "Actief"), ("all", "Alle"), ("new", "Nieuw"), ("open", "Open"), ("pending", "Wacht"), ("closed", "Gesloten"),
    ]
    static let statuses: [(key: String, label: String)] = [
        ("new", "Nieuw"), ("open", "Open"), ("pending", "Wacht op reactie"), ("closed", "Gesloten"),
    ]
    static let priorities: [(key: String, label: String)] = [
        ("low", "Laag"), ("normal", "Normaal"), ("high", "Hoog"), ("urgent", "Dringend"),
    ]

    static func status(_ key: String?) -> String {
        statuses.first { $0.key == key }.map { String(localized: String.LocalizationValue($0.label)) } ?? (key ?? "")
    }

    static func campaignStatus(_ key: String?) -> String {
        switch key {
        case "draft": return String(localized: "concept")
        case "sending": return String(localized: "wordt verstuurd")
        case "sent": return String(localized: "verstuurd")
        case "cancelled": return String(localized: "geannuleerd")
        default: return key ?? ""
        }
    }

    static func audience(_ key: String?) -> String {
        switch key {
        case "users": return String(localized: "Gebruikers")
        case "owners": return String(localized: "Ondernemers")
        case "list": return String(localized: "Lijst")
        default: return key ?? ""
        }
    }
}
