import Foundation

enum BarcodeFormat: String, CaseIterable, Identifiable, Codable {
    case ean13, ean8, upcA, code128, code39, itf, qr, pdf417, aztec

    var id: String { rawValue }

    /// Drawn as bars by `BarcodeEncoder`; the others are 2D codes.
    var isLinear: Bool {
        switch self {
        case .ean13, .ean8, .upcA, .code128, .code39, .itf: true
        case .qr, .pdf417, .aztec: false
        }
    }

    var displayName: String {
        switch self {
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .upcA: "UPC-A"
        case .code128: "Code 128"
        case .code39: "Code 39"
        case .itf: "ITF"
        case .qr: "QR"
        case .pdf417: "PDF417"
        case .aztec: "Aztec"
        }
    }

    /// Best format for a number typed by hand.
    static func guess(for value: String) -> BarcodeFormat {
        let digitsOnly = !value.isEmpty && value.allSatisfy { ("0"..."9").contains($0) }
        if digitsOnly {
            if value.count == 13, (try? BarcodeEncoder.ean13(value)) != nil,
               BarcodeEncoder.gs1CheckDigit(String(value.prefix(12))) == Int(String(value.last!)) { return .ean13 }
            if value.count == 8,
               BarcodeEncoder.gs1CheckDigit(String(value.prefix(7))) == Int(String(value.last!)) { return .ean8 }
        }
        return .code128
    }
}

/// Soort pas. Wordt als tekst bewaard (kindRaw) en gesynchroniseerd: een onbekende waarde (van een nieuwere versie)
/// leest elke versie als klantenkaart, zonder dat er iets breekt. Kortingscode, ticket en abonnement zijn er sinds 1.0.2;
/// oudere versies tonen die als klantenkaart.
enum CardKind: String, CaseIterable, Identifiable, Codable {
    case loyalty, voucher, code, ticket, subscription

    var id: String { rawValue }

    /// De soorten die niet in de winkellijst staan (je voegt ze zelf toe).
    static let others: [CardKind] = [.code, .ticket, .subscription]

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CardKind(rawValue: raw) ?? .loyalty
    }

    var displayName: String {
        switch self {
        case .loyalty: String(localized: "Klantenkaart")
        case .voucher: String(localized: "Voucher")
        case .code: String(localized: "Kortingscode")
        case .ticket: String(localized: "Ticket")
        case .subscription: String(localized: "Abonnement")
        }
    }

    var symbol: String {
        switch self {
        case .loyalty: "creditcard"
        case .voucher: "giftcard"
        case .code: "tag"
        case .ticket: "ticket"
        case .subscription: "arrow.triangle.2.circlepath"
        }
    }

    /// Heeft een vervaldatum (en dus een herinnering als hij bijna verloopt).
    var hasExpiry: Bool { self == .voucher || self == .code }

    /// Hoe de code heet in het formulier en op de kaart.
    var codeLabel: String {
        switch self {
        case .loyalty: String(localized: "Kaartnummer")
        case .voucher: String(localized: "Kaartnummer")
        case .code: String(localized: "Code")
        case .ticket: String(localized: "Ticketcode")
        case .subscription: String(localized: "Lidnummer")
        }
    }
}
