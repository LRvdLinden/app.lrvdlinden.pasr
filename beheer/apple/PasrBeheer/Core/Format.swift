import Foundation

enum Fmt {
    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.numberStyle = .decimal
        return f
    }()

    static func n(_ v: Int) -> String { number.string(from: NSNumber(value: v)) ?? "\(v)" }

    static func plural(_ v: Int, _ one: String, _ many: String) -> String { "\(n(v)) \(v == 1 ? one : many)" }

    /// "zojuist", "5 min geleden", "3 dagen geleden", of een datum.
    static func ago(_ iso: String?) -> String {
        guard let date = DateParse.date(iso) else { return "nooit" }
        let s = Date.now.timeIntervalSince(date)
        switch s {
        case ..<60: return "zojuist"
        case ..<3600: return "\(Int(s / 60)) min geleden"
        case ..<86_400: return "\(Int(s / 3600)) uur geleden"
        case ..<(86_400 * 30):
            let d = Int(s / 86_400)
            return d == 1 ? "1 dag geleden" : "\(d) dagen geleden"
        default: return date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "nl_NL")))
        }
    }

    /// 🇳🇱 voor "NL".
    static func flag(_ code: String) -> String {
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return "🌐" }
        return String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }))
    }

    static func country(_ code: String) -> String {
        code == "?" ? "Onbekend" : (Locale(identifier: "nl_NL").localizedString(forRegionCode: code) ?? code)
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "nl_NL")))
    }

    static func period(_ r: Stats.Range) -> String {
        guard let a = DateParse.day(r.from), let b = DateParse.day(r.to) else { return "" }
        let nl = Locale(identifier: "nl_NL")
        var f = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(nl)
        f.timeZone = TimeZone(identifier: "UTC")!
        var g = f.year()
        g.timeZone = TimeZone(identifier: "UTC")!
        return "\(a.formatted(f)) – \(b.formatted(g))"
    }
}
