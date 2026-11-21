import Foundation
import Compression
import UniformTypeIdentifiers

/// Kaarten uit een bestand: een CSV of JSON (export van een andere app, of zelf gemaakt) of een Apple Wallet-pas
/// (.pkpass). Alles wordt op het apparaat gelezen. Pasr kent geen geheime formaten van andere apps: het leest
/// kolommen of velden met gangbare namen (naam, nummer, formaat, ...), zie `WalletImport.exampleCSV`.
enum WalletImport {
    struct Item {
        var storeName: String
        var number: String
        var format: BarcodeFormat?
        var kind: CardKind?
        var colorHex: String?
        var balance: Double?
        var expiresAt: Date?
        var note: String = ""
        var details: CardDetails?
        var logo: Data?
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var fileTypes: [UTType] {
        [.commaSeparatedText, .tabSeparatedText, .json, .plainText, UTType(filenameExtension: "pkpass")].compactMap { $0 }
    }

    /// Voorbeeld voor de algemene CSV-import (puntkomma of komma als scheiding, eerste regel = kolomnamen).
    static let exampleCSV = """
    naam;nummer;formaat;soort;saldo;vervaldatum;notitie
    Albert Heijn;2620123456782;ean13;klantenkaart;;;
    Bol cadeaukaart;6064001234567890;code128;cadeaukaart;25,00;2027-06-30;Verjaardag
    Zalando;WELKOM10;tekst;kortingscode;;2026-12-31;10% korting
    """

    static func read(_ data: Data, fileName: String) throws -> [Item] {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "pkpass" || data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return [try pkpass(data)]
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw Failure(message: String(localized: "Dit bestand kan Pasr niet lezen."))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ext == "json" || trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            return try json(data)
        }
        return try csv(trimmed)
    }

    // MARK: Velden herkennen

    private static let nameKeys = ["naam", "name", "winkel", "store", "storename", "store_name", "merchant", "brand", "title",
                                   "titel", "programma", "program", "card_name", "cardname", "organizationname", "organization"]
    private static let numberKeys = ["nummer", "number", "kaartnummer", "cardnumber", "card_number", "code", "barcode",
                                     "barcodevalue", "barcode_value", "value", "waarde", "klantnummer", "membernumber", "member_number"]
    private static let formatKeys = ["formaat", "format", "barcodeformat", "barcode_format", "type_code", "codetype", "code_type", "symbology"]
    private static let kindKeys = ["soort", "kind", "type", "cardtype", "card_type", "categorie", "category"]
    private static let balanceKeys = ["saldo", "balance", "tegoed", "amount", "bedrag"]
    private static let expiryKeys = ["vervaldatum", "expires", "expiry", "expiresat", "expires_at", "expiration", "expirationdate",
                                     "expiration_date", "geldig_tot", "geldigtot", "valid_until", "validuntil"]
    private static let noteKeys = ["notitie", "note", "notes", "opmerking", "description", "omschrijving"]
    private static let colorKeys = ["kleur", "color", "colour", "colorhex", "color_hex", "backgroundcolor"]

    private static func norm(_ key: String) -> String {
        key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'\u{FEFF}")))
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func value(_ row: [String: String], _ keys: [String]) -> String? {
        for k in keys { if let v = row[k]?.trimmingCharacters(in: .whitespaces), !v.isEmpty { return v } }
        let compact = row.reduce(into: [String: String]()) { $0[$1.key.replacingOccurrences(of: "_", with: "")] = $1.value }
        for k in keys { if let v = compact[k.replacingOccurrences(of: "_", with: "")]?.trimmingCharacters(in: .whitespaces), !v.isEmpty { return v } }
        return nil
    }

    static func parseFormat(_ raw: String?) -> BarcodeFormat? {
        guard let raw else { return nil }
        let s = raw.lowercased().replacingOccurrences(of: "pkbarcodeformat", with: "")
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "")
        switch s {
        case "ean13", "ean": return .ean13
        case "ean8": return .ean8
        case "upca", "upc": return .upcA
        case "code128", "128": return .code128
        case "code39", "39": return .code39
        case "itf", "itf14", "interleaved2of5", "i2of5": return .itf
        case "qr", "qrcode": return .qr
        case "pdf417", "pdf": return .pdf417
        case "aztec": return .aztec
        default: return nil
        }
    }

    static func parseKind(_ raw: String?) -> CardKind? {
        guard let s = raw?.lowercased() else { return nil }
        if s.contains("cadeau") || s.contains("gift") || s.contains("voucher") || s.contains("tegoed") { return .voucher }
        if s.contains("korting") || s.contains("coupon") || s.contains("discount") || s.contains("promo") { return .code }
        if s.contains("ticket") || s.contains("event") || s.contains("boarding") || s.contains("toegang") { return .ticket }
        if s.contains("abonnement") || s.contains("subscription") || s.contains("lidmaatschap") || s.contains("membership") { return .subscription }
        if s.contains("klant") || s.contains("loyal") || s.contains("store") || s.contains("spaar") { return .loyalty }
        return nil
    }

    static func parseAmount(_ raw: String?) -> Double? {
        guard var s = raw?.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "EUR", with: "")
            .trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.contains(","), s.contains(".") { s = s.replacingOccurrences(of: ".", with: "") }   // 1.234,56
        s = s.replacingOccurrences(of: ",", with: ".")
        return Double(s.filter { $0.isNumber || $0 == "." || $0 == "-" })
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for pattern in ["yyyy-MM-dd", "dd-MM-yyyy", "d-M-yyyy", "dd/MM/yyyy", "d/M/yyyy", "dd.MM.yyyy", "yyyy-MM-dd HH:mm:ss"] {
            f.dateFormat = pattern
            if let d = f.date(from: s) { return d }
        }
        if let n = Double(s), n > 1_000_000_000 { return Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n) }
        return nil
    }

    private static func color(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#"), s.count == 7 { return s.uppercased() }
        if s.count == 6, s.allSatisfy(\.isHexDigit) { return "#" + s.uppercased() }
        return rgb(s)
    }

    /// "rgb(12, 34, 56)" (Wallet) als #0C2238.
    static func rgb(_ s: String) -> String? {
        let parts = s.lowercased().replacingOccurrences(of: "rgba", with: "").replacingOccurrences(of: "rgb", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "() ")).split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", min(255, max(0, parts[0])), min(255, max(0, parts[1])), min(255, max(0, parts[2])))
    }

    private static func item(from row: [String: String]) -> Item? {
        guard let number = value(row, numberKeys) else { return nil }
        let name = value(row, nameKeys) ?? String(localized: "Kaart")
        let rawFormat = value(row, formatKeys)
        var kind = parseKind(value(row, kindKeys))
        let textCode = ["tekst", "text", "none", "geen"].contains(rawFormat?.lowercased() ?? "")
        if textCode, kind == nil { kind = .code }
        var item = Item(storeName: String(name.prefix(60)), number: String(number.prefix(200)), format: parseFormat(rawFormat),
                        kind: kind, colorHex: color(value(row, colorKeys)), balance: parseAmount(value(row, balanceKeys)),
                        expiresAt: parseDate(value(row, expiryKeys)), note: String((value(row, noteKeys) ?? "").prefix(500)))
        if kind == .code {
            var d = CardDetails()
            d.codeAsBarcode = textCode || item.format == nil ? nil : true
            item.details = d
        }
        return item
    }

    // MARK: CSV

    static func csv(_ text: String) throws -> [Item] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first else { throw Failure(message: String(localized: "Het bestand is leeg.")) }
        let candidates: [Character] = [";", "\t", ","]
        let separator: Character = candidates.max { a, b in header.filter { $0 == a }.count < header.filter { $0 == b }.count } ?? ";"
        let keys = fields(header, separator).map(norm)
        guard keys.contains(where: { numberKeys.contains($0) || numberKeys.contains($0.replacingOccurrences(of: "_", with: "")) }) else {
            throw Failure(message: String(localized: "Geen kolom met het nummer gevonden. De eerste regel moet de kolomnamen bevatten, met in elk geval naam en nummer."))
        }
        return lines.dropFirst().compactMap { line in
            let values = fields(line, separator)
            var row: [String: String] = [:]
            for (i, key) in keys.enumerated() where i < values.count { row[key] = values[i] }
            return item(from: row)
        }
    }

    /// Velden van één regel, met "aanhalingstekens" (en "" binnen een veld).
    static func fields(_ line: String, _ separator: Character) -> [String] {
        var out: [String] = [], current = "", quoted = false
        var chars = Array(line)[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { current.append("\""); chars.removeFirst() } else { quoted = false }
                } else { current.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == separator { out.append(current); current = "" }
            else { current.append(c) }
        }
        out.append(current)
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: JSON

    static func json(_ data: Data) throws -> [Item] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw Failure(message: String(localized: "Dit JSON-bestand kan Pasr niet lezen."))
        }
        var list: [[String: Any]] = []
        if let array = root as? [[String: Any]] { list = array }
        else if let dict = root as? [String: Any] {
            // {"cards": [...]} of een andere lijst op het eerste niveau
            list = (dict["cards"] ?? dict["kaarten"] ?? dict["items"] ?? dict["data"]) as? [[String: Any]]
                ?? dict.values.compactMap { $0 as? [[String: Any]] }.first ?? []
        }
        let items = list.compactMap { obj -> Item? in
            var row: [String: String] = [:]
            func flatten(_ o: [String: Any], prefix: String = "") {
                for (k, v) in o {
                    let key = norm(k)
                    switch v {
                    case let s as String: row[key] = row[key] ?? s
                    case let n as NSNumber: row[key] = row[key] ?? n.stringValue
                    case let d as [String: Any] where prefix.isEmpty: flatten(d, prefix: key)   // {"barcode": {"value": …}}
                    default: break
                    }
                }
            }
            flatten(obj)
            return item(from: row)
        }
        if items.isEmpty { throw Failure(message: String(localized: "Geen kaarten met een nummer gevonden in dit bestand.")) }
        return items
    }

    // MARK: Apple Wallet (.pkpass)

    static func pkpass(_ data: Data) throws -> Item {
        let files = Zip.entries(data)
        guard let passData = files["pass.json"].flatMap({ Zip.extract($0, from: data) }),
              let pass = try? JSONSerialization.jsonObject(with: passData) as? [String: Any] else {
            throw Failure(message: String(localized: "Dit is geen geldige Apple Wallet-pas."))
        }
        let barcodes = (pass["barcodes"] as? [[String: Any]]) ?? (pass["barcode"] as? [String: Any]).map { [$0] } ?? []
        let code = barcodes.first
        let message = code?["message"] as? String
        let name = (pass["logoText"] as? String) ?? (pass["organizationName"] as? String) ?? (pass["description"] as? String) ?? "Pas"
        var kind: CardKind = .loyalty
        var details = CardDetails()
        if pass["eventTicket"] != nil || pass["boardingPass"] != nil {
            kind = .ticket
            details.eventDate = (pass["relevantDate"] as? String).flatMap(parseDate)
            if let locations = pass["locations"] as? [[String: Any]], let text = locations.first?["relevantText"] as? String {
                details.venue = String(text.prefix(80))
            }
        } else if pass["coupon"] != nil {
            kind = .code
            details.codeAsBarcode = message == nil ? nil : true
        }
        // een pas zonder barcode: het eerste veld met een waarde (vaak het nummer)
        var number = message
        if number == nil {
            for style in ["storeCard", "coupon", "eventTicket", "generic", "boardingPass"] {
                guard let s = pass[style] as? [String: Any] else { continue }
                for group in ["primaryFields", "secondaryFields", "auxiliaryFields"] {
                    if let v = (s[group] as? [[String: Any]])?.first?["value"] { number = "\(v)"; break }
                }
                if number != nil { break }
            }
        }
        guard let number, !number.isEmpty else { throw Failure(message: String(localized: "Deze pas heeft geen code die Pasr kan overnemen.")) }
        let logo = ["logo@3x.png", "logo@2x.png", "logo.png"].lazy.compactMap { files[$0].flatMap { Zip.extract($0, from: data) } }.first
        return Item(storeName: String(name.prefix(60)), number: number, format: parseFormat(code?["format"] as? String) ?? (message == nil ? nil : .qr),
                    kind: kind, colorHex: (pass["backgroundColor"] as? String).flatMap(rgb),
                    expiresAt: (pass["expirationDate"] as? String).flatMap(parseDate), details: details.isEmpty ? nil : details, logo: logo)
    }
}

/// Een heel klein zip-leesprogramma (alleen wat een .pkpass nodig heeft: opgeslagen of deflate).
enum Zip {
    struct Entry {
        var method: UInt16
        var compressedSize: Int
        var size: Int
        var headerOffset: Int
    }

    private static func u16(_ d: Data, _ o: Int) -> UInt16 {
        guard o + 2 <= d.count else { return 0 }
        return UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8
    }

    private static func u32(_ d: Data, _ o: Int) -> UInt32 {
        guard o + 4 <= d.count else { return 0 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(d[d.startIndex + o + $1]) << (8 * UInt32($1)) }
    }

    /// Bestanden uit de centrale lijst aan het eind van het zip-bestand.
    static func entries(_ d: Data) -> [String: Entry] {
        guard d.count > 22 else { return [:] }
        var end = -1
        for o in stride(from: d.count - 22, through: max(0, d.count - 65_557), by: -1) where u32(d, o) == 0x06054b50 { end = o; break }
        guard end >= 0 else { return [:] }
        let count = Int(u16(d, end + 10))
        var o = Int(u32(d, end + 16))
        var out: [String: Entry] = [:]
        for _ in 0..<min(count, 500) {
            guard u32(d, o) == 0x02014b50 else { break }
            let nameLength = Int(u16(d, o + 28)), extra = Int(u16(d, o + 30)), comment = Int(u16(d, o + 32))
            guard o + 46 + nameLength <= d.count else { break }
            let name = String(decoding: d[(d.startIndex + o + 46)..<(d.startIndex + o + 46 + nameLength)], as: UTF8.self)
            out[name] = Entry(method: u16(d, o + 10), compressedSize: Int(u32(d, o + 20)), size: Int(u32(d, o + 24)),
                              headerOffset: Int(u32(d, o + 42)))
            o += 46 + nameLength + extra + comment
        }
        return out
    }

    static func extract(_ e: Entry, from d: Data) -> Data? {
        let o = e.headerOffset
        guard u32(d, o) == 0x04034b50, e.size <= 20_000_000 else { return nil }
        let start = o + 30 + Int(u16(d, o + 26)) + Int(u16(d, o + 28))
        guard start + e.compressedSize <= d.count else { return nil }
        let raw = d[(d.startIndex + start)..<(d.startIndex + start + e.compressedSize)]
        switch e.method {
        case 0: return Data(raw)
        case 8:
            guard e.size > 0 else { return Data() }
            var out = Data(count: e.size)
            let written = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
                }
            }
            return written == e.size ? out : nil
        default: return nil
        }
    }
}
