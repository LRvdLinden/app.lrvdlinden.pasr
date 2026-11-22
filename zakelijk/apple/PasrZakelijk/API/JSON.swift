import Foundation

/// Losse JSON-lezer: elk veld optioneel, meerdere namen voor hetzelfde veld, zodat een kleine naamswijziging op de
/// server de app niet breekt.
struct JSONObject {
    let raw: [String: Any]

    init?(_ any: Any?) {
        if let d = any as? [String: Any] { raw = d }
        else if let list = any as? [[String: Any]], let first = list.first { raw = first }
        else { return nil }
    }

    func string(_ keys: String...) -> String? {
        for k in keys {
            if let v = raw[k] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty { return v }
            if let v = raw[k] as? NSNumber { return v.stringValue }
        }
        return nil
    }

    func int(_ keys: String...) -> Int? {
        for k in keys {
            if let v = raw[k] as? NSNumber { return v.intValue }
            if let v = raw[k] as? String, let i = Int(v) { return i }
        }
        return nil
    }

    func bool(_ keys: String...) -> Bool? {
        for k in keys {
            if let v = raw[k] as? Bool { return v }
            if let v = raw[k] as? NSNumber { return v.boolValue }
            if let v = raw[k] as? String { return ["true", "t", "1", "yes"].contains(v.lowercased()) }
        }
        return nil
    }

    func date(_ keys: String...) -> Date? {
        for k in keys { if let s = raw[k] as? String, let d = JSONDates.parse(s) { return d } }
        return nil
    }

    func object(_ keys: String...) -> JSONObject? {
        for k in keys { if let d = raw[k] as? [String: Any] { return JSONObject(d) } }
        return nil
    }

    func array(_ keys: String...) -> [JSONObject] {
        for k in keys { if let list = raw[k] as? [Any] { return list.compactMap { JSONObject($0) } } }
        return []
    }

    func has(_ key: String) -> Bool { raw[key] != nil && !(raw[key] is NSNull) }
}

enum JSONDates {
    private static let full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "2026-11-22T10:11:12.123456+00:00", "2026-11-22 10:11:12+00", "2026-11-22".
    static func parse(_ value: String) -> Date? {
        var s = value.trimmingCharacters(in: .whitespaces)
        if s.count == 10 { return day.date(from: s) }
        s = s.replacingOccurrences(of: " ", with: "T")
        // fracties inkorten tot milliseconden
        if let r = s.range(of: "\\.[0-9]+", options: .regularExpression) {
            let frac = String(s[r].prefix(4))
            s.replaceSubrange(r, with: frac)
        }
        // "+00" → "+00:00"
        if s.range(of: "[+-][0-9]{2}$", options: .regularExpression) != nil { s += ":00" }
        return full.date(from: s) ?? plain.date(from: s)
    }
}
