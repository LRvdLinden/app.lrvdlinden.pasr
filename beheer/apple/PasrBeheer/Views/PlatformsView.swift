import Charts
import SwiftUI

/// Antwoord van de actie `platforms` (databasefunctie pasr_admin_platforms): Pasr en Pasr Zakelijk op iOS en Android.
struct Platforms: Decodable {
    struct Count: Decodable {
        var devices = 0, active_1 = 0, active_7 = 0, active_30 = 0, new_period = 0, signed_in = 0
    }
    struct PerOS: Decodable {
        var ios: Count? = nil
        var android: Count? = nil
    }
    struct Apps: Decodable {
        var pasr: PerOS? = nil
        var zakelijk: PerOS? = nil
    }
    struct Version: Decodable, Identifiable {
        let app: String
        let platform: String
        let version: String
        var build: String? = nil
        var devices = 0
        var active_30 = 0
        var id: String { "\(app)|\(platform)|\(version)|\(build ?? "")" }
        var title: String {
            "\(app == "zakelijk" ? "Zakelijk" : "Pasr") \(platform == "android" ? "Android" : "iOS") \(version)"
                + ((build ?? "").isEmpty ? "" : " (\(build!))")
        }
    }
    struct Accounts: Decodable {
        var ios = 0, android = 0, web = 0, other = 0
    }
    struct Day: Decodable, Identifiable {
        let day: String
        var pasr_ios = 0, pasr_android = 0, zakelijk_ios = 0, zakelijk_android = 0, new_ios = 0, new_android = 0, gwallet = 0, wallet = 0
        var id: String { day }
        var date: Date { DateParse.day(day) ?? .distantPast }
    }
    struct GWallet: Decodable {
        var objects = 0, updated_30 = 0, period = 0
    }

    var days: Int? = nil
    var apps: Apps? = nil
    var versions: [Version]? = nil
    var accounts: Accounts? = nil
    var series: [Day]? = nil
    var gwallet: GWallet? = nil
    var gwallet_ready: Bool? = nil
}

/// iOS en Android in Homey Insights-stijl: actieve toestellen per dag (iOS en Android gestapeld, met kruisdraad),
/// nieuwe installaties, Google Wallet-passen, accounts per platform en de versies die in gebruik zijn.
struct PlatformsCard: View {
    @EnvironmentObject private var session: Session
    var days: Int
    @State private var data: Platforms?
    @State private var error: String?
    @State private var selected: Date?
    @State private var app = "pasr"

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("iOS en Android").font(.headline)
                    Spacer()
                    Picker("App", selection: $app) {
                        Text("Pasr").tag("pasr")
                        Text("Zakelijk").tag("zakelijk")
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 200)
                }
                if let error {
                    Text(error).font(.subheadline).foregroundStyle(Theme.coral)
                } else if let data {
                    kpis(data)
                    activeChart(data)
                    Divider().overlay(Theme.line)
                    walletChart(data)
                    Divider().overlay(Theme.line)
                    lists(data)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .task(id: "\(days)|\(session.refreshTick)") { await load() }
    }

    private func load() async {
        do {
            let d = try await session.call("platforms", ["days": days], as: Platforms.self)
            withAnimation(.snappy) { data = d }
            error = nil
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch {
            self.error = "Platformen: \(error.localizedDescription)"
        }
    }

    private func count(_ d: Platforms, _ os: String) -> Platforms.Count {
        let per = app == "zakelijk" ? d.apps?.zakelijk : d.apps?.pasr
        return (os == "android" ? per?.android : per?.ios) ?? Platforms.Count()
    }

    private func kpis(_ d: Platforms) -> some View {
        let ios = count(d, "ios"), android = count(d, "android")
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            KPITile(title: "Android actief", value: Fmt.n(android.active_30), detail: "30 dagen · \(Fmt.n(android.active_1)) vandaag", color: Color(hex: 0x2BB38A))
            KPITile(title: "iOS actief", value: Fmt.n(ios.active_30), detail: "30 dagen · \(Fmt.n(ios.active_1)) vandaag", color: Theme.iris)
            KPITile(title: "Nieuwe installaties", value: Fmt.n(android.new_period + ios.new_period),
                    detail: "Android \(Fmt.n(android.new_period)) · iOS \(Fmt.n(ios.new_period))", color: Theme.mint)
            KPITile(title: "Google Wallet", value: Fmt.n(d.gwallet?.objects ?? 0),
                    detail: d.gwallet_ready == false ? "nog niet ingericht" : "\(Fmt.n(d.gwallet?.updated_30 ?? 0)) bijgewerkt, 30 dagen", color: Color(hex: 0x0E8A62))
        }
    }

    private struct Bar: Identifiable {
        let date: Date
        let os: String
        let value: Int
        var id: String { "\(date.timeIntervalSince1970)\(os)" }
    }

    private func activeChart(_ d: Platforms) -> some View {
        let rows = d.series ?? []
        let bars = rows.flatMap { r -> [Bar] in
            let ios = app == "zakelijk" ? r.zakelijk_ios : r.pasr_ios
            let android = app == "zakelijk" ? r.zakelijk_android : r.pasr_android
            return [Bar(date: r.date, os: "iOS", value: ios), Bar(date: r.date, os: "Android", value: android)]
        }
        let picked = selected.flatMap { s in rows.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Dot(color: Color(hex: 0x2BB38A)); Text("Android").font(.caption)
                Dot(color: Theme.iris); Text("iOS").font(.caption)
                Text("· actieve toestellen per dag").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if let picked {
                    let ios = app == "zakelijk" ? picked.zakelijk_ios : picked.pasr_ios
                    let android = app == "zakelijk" ? picked.zakelijk_android : picked.pasr_android
                    Text("\(picked.date.formatted(.dateTime.day().month(.abbreviated))): Android \(android) · iOS \(ios)").font(.caption.monospacedDigit().weight(.semibold))
                }
            }
            Chart(bars) { b in
                BarMark(x: .value("Dag", b.date, unit: .day), y: .value("Toestellen", b.value))
                    .foregroundStyle(by: .value("Platform", b.os))
                    .opacity(picked == nil || Calendar.utc.isDate(b.date, inSameDayAs: picked!.date) ? 1 : 0.35)
                if let picked {
                    RuleMark(x: .value("Dag", picked.date, unit: .day)).foregroundStyle(Theme.muted.opacity(0.6))
                }
            }
            .chartForegroundStyleScale(["Android": Color(hex: 0x2BB38A), "iOS": Theme.iris])
            .chartLegend(.hidden)
            .chartXSelection(value: $selected)
            .frame(height: 170)
        }
    }

    private func walletChart(_ d: Platforms) -> some View {
        let rows = d.series ?? []
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Dot(color: Color(hex: 0x0E8A62)); Text("Google Wallet").font(.caption)
                Dot(color: Theme.sky); Text("Apple Wallet").font(.caption)
                Text("· passen gemaakt per dag").font(.caption).foregroundStyle(Theme.muted)
            }
            Chart {
                ForEach(rows) { r in
                    BarMark(x: .value("Dag", r.date, unit: .day), y: .value("Passen", r.gwallet)).foregroundStyle(by: .value("Wallet", "Google"))
                    BarMark(x: .value("Dag", r.date, unit: .day), y: .value("Passen", r.wallet)).foregroundStyle(by: .value("Wallet", "Apple"))
                }
            }
            .chartForegroundStyleScale(["Google": Color(hex: 0x0E8A62), "Apple": Theme.sky])
            .chartLegend(.hidden)
            .frame(height: 120)
        }
    }

    private func lists(_ d: Platforms) -> some View {
        let acc = d.accounts ?? Platforms.Accounts()
        let accRows: [(String, Int)] = [("iOS", acc.ios), ("Android", acc.android), ("Web", acc.web), ("Van voor de telling", acc.other)]
        let accTotal = accRows.reduce(0) { $0 + $1.1 }, accTop = accRows.map(\.1).max() ?? 0
        let vers = (d.versions ?? []).filter { $0.app == app }.sorted { $0.active_30 > $1.active_30 }.prefix(8)
        let vTotal = vers.reduce(0) { $0 + $1.active_30 }, vTop = vers.map(\.active_30).max() ?? 0
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) { accountsList(accRows, accTotal, accTop); versionsList(Array(vers), vTotal, vTop) }
            VStack(alignment: .leading, spacing: 16) { accountsList(accRows, accTotal, accTop); versionsList(Array(vers), vTotal, vTop) }
        }
    }

    private func accountsList(_ rows: [(String, Int)], _ total: Int, _ top: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts aangemaakt op").font(.subheadline.weight(.semibold))
            ForEach(rows, id: \.0) { r in DistRow(label: r.0, value: r.1, total: total, max: top, color: Theme.iris2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func versionsList(_ rows: [Platforms.Version], _ total: Int, _ top: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Versies (actief, 30 dagen)").font(.subheadline.weight(.semibold))
            if rows.isEmpty {
                Text("Nog geen versies gemeld.").font(.subheadline).foregroundStyle(Theme.muted)
            } else {
                ForEach(rows) { v in DistRow(label: v.title, value: v.active_30, total: total, max: top, color: v.platform == "android" ? Color(hex: 0x2BB38A) : Theme.iris) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Kleurvakje in de legenda (staven).
private struct Dot: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
    }
}
