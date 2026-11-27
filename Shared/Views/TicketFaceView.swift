import SwiftUI

/// Een ticket zoals een eventTicket in Apple Wallet: bovenaan de huisstijl van het evenement (logo, naam, titel, soort
/// ticket, datum, toegang en locatie), een golvende rand in de merkkleur, uitsparingen aan de zijkanten en daaronder
/// het deel met de QR-code van de bezoeker. Herbruikbaar: de stapel (`.front`), de achterkant op kaartformaat
/// (`.code`, Watch/widgets/omdraaien) en het detail (`.full`, met de knoppen Route en Informatie).
///
///     TicketFaceView(card: card)                        // detail, hoog
///     TicketFaceView(card: card, layout: .front)        // in een stapel of raster, op kaartformaat
struct TicketFaceView: View {
    enum Layout { case front, code, full }

    let appearance: CardAppearance
    var layout: Layout = .full
    /// Face ID is gelukt (vergrendelde kaart): pas dan de code.
    var revealed = true
    var cornerRadius: CGFloat = 20
    /// Alleen in voorbeelden en schermafbeeldingen: "DEMO – geen toegangsbewijs" bij de code.
    var demo = false
    /// Knoppen Route en Informatie (alleen bij `.full`).
    var showsActions = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(\.codeShield) private var codeShield
    @State private var headHeight: CGFloat = 0

    init(appearance: CardAppearance, layout: Layout = .full, revealed: Bool = true, cornerRadius: CGFloat = 20,
         demo: Bool = false, showsActions: Bool = true) {
        self.appearance = appearance
        self.layout = layout
        self.revealed = revealed
        self.cornerRadius = cornerRadius
        self.demo = demo
        self.showsActions = showsActions
    }

    init(card: Card, layout: Layout = .full, revealed: Bool = true, demo: Bool = false) {
        self.init(appearance: CardAppearance(card), layout: layout, revealed: revealed, demo: demo)
    }

    private var ticket: TicketInfo {
        appearance.ticket ?? TicketInfo.resolve(name: appearance.storeName, templateID: nil, details: appearance.details)
    }
    private var brandColor: Color { Color(hex: appearance.colorHex) }
    private var ink: Color { ticket.textHex.map(Color.init(hex:)) ?? Color.onCard(appearance.colorHex) }
    private var label: Color { ticket.labelHex.map(Color.init(hex:)) ?? ink.opacity(0.72) }
    /// Het codedeel: wit in licht, bijna zwart in donker (de QR-code zelf staat altijd op wit).
    private var paper: Color { scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : .white }
    private var paperInk: Color { scheme == .dark ? .white : Color(hex: "#111216") }

    var body: some View {
        Group {
            switch layout {
            case .front: front
            case .code: compactCode
            case .full: full
            }
        }
        .accessibilityElement(children: layout == .full ? .contain : .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    // MARK: Lagen

    /// Op kaartformaat, helemaal in de merkkleur: zo herken je in de stapel meteen een ticket.
    private var front: some View {
        GeometryReader { geo in
            let stub = geo.size.height * 0.30
            ZStack(alignment: .topLeading) {
                brandColor
                VStack(alignment: .leading, spacing: 0) {
                    header(compact: true)
                    Spacer(minLength: 4)
                    Text(ticket.title)
                        .font(.system(size: min(26, geo.size.width * 0.075), weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        typePill(small: true)
                        statusBadge(small: true)
                    }
                    .padding(.top, 5)
                    Spacer(minLength: 4)
                    // strookje onder de perforatie: datum, toegang, locatie
                    HStack(alignment: .top, spacing: 12) {
                        if let d = ticket.dateText { field("DATUM", d, small: true) }
                        if let t = ticket.timeText { field(timeLabel, t, small: true) }
                        if let p = ticket.place { field("LOCATIE", p, small: true).layoutPriority(-1) }
                    }
                    .frame(height: stub - 14, alignment: .center)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
                Perforation()
                    .stroke(ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .offset(y: geo.size.height - stub)
            }
            .foregroundStyle(ink)
            .clipShape(TicketShape(notchY: geo.size.height - stub, cornerRadius: cornerRadius), style: FillStyle(eoFill: true))
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    /// Achterkant op kaartformaat (omdraaien, Watch, widgets): kop met golf, daaronder de code en de gegevens.
    private var compactCode: some View {
        GeometryReader { geo in
            let head = geo.size.height * 0.30
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    brandColor
                    header(compact: true).padding(.horizontal, 12)
                }
                .foregroundStyle(ink)
                .frame(height: head)
                Wave().fill(brandColor).frame(height: 10).background(paper)
                HStack(alignment: .center, spacing: 12) {
                    codeArea(compact: true)
                        .frame(width: geo.size.height * 0.52, height: geo.size.height * 0.52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ticket.title)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let type = ticket.type {
                            Text([type, ticket.note].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2.weight(.semibold)).lineLimit(1)
                                .foregroundStyle(brandText)
                        }
                        if let d = ticket.dateText { Text(d).font(.caption2).lineLimit(1) }
                        if let t = ticket.timeText { Text(t).font(.caption2).lineLimit(1) }
                        if let p = ticket.place { Text(p).font(.caption2).lineLimit(1).opacity(0.8) }
                    }
                    .foregroundStyle(paperInk)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background(paper)
            }
            .clipShape(TicketShape(notchY: head + 5, cornerRadius: cornerRadius), style: FillStyle(eoFill: true))
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    /// Hoog ticket voor het detail, zoals het voorbeeld: kop, golf, QR-deel en de knoppen.
    private var full: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header(compact: false)
                VStack(alignment: .leading, spacing: 8) {
                    Text(ticket.title)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 8) {
                        typePill(small: false)
                        statusBadge(small: false)
                    }
                }
                fieldsGrid
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { headBackground }
            .foregroundStyle(ink)
            .background(GeometryReader { g in Color.clear.preference(key: TicketHeadKey.self, value: g.size.height) })

            Wave().fill(brandColor).frame(height: 18).background(paper)

            VStack(spacing: 12) {
                codeArea(compact: false)
                    .frame(maxWidth: 230)
                    .padding(.top, 6)
                if demo {
                    Text("DEMO – geen toegangsbewijs")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(Color(hex: "#C8372F"))
                }
                Text("Pasr")
                    .font(.system(.footnote, design: .rounded).weight(.heavy))
                    .foregroundStyle(paperInk.opacity(0.45))
                if showsActions && (ticket.routeURL != nil || ticket.info != nil) {
                    HStack(spacing: 10) {
                        if let route = ticket.routeURL {
                            actionButton("Route", symbol: "map.fill") { openURL(route) }
                        }
                        if let info = ticket.info {
                            actionButton("Informatie", symbol: "info.circle.fill") { openURL(info) }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background(paper)
        }
        .onPreferenceChange(TicketHeadKey.self) { headHeight = $0 }
        .clipShape(TicketShape(notchY: headHeight + 9, cornerRadius: cornerRadius), style: FillStyle(eoFill: true))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
    }

    // MARK: Onderdelen

    /// Merkkleur, met de headerafbeelding van het event erachter als die er is.
    private var headBackground: some View {
        ZStack {
            brandColor
            if let header = ticket.header {
                AsyncImage(url: header) { image in
                    image.resizable().scaledToFill().overlay(brandColor.opacity(0.6))
                } placeholder: {
                    Color.clear
                }
            }
        }
        .clipped()
    }

    /// Merkkleur als tekstkleur op het witte deel; te licht (geel, wit) dan gewoon de tekstkleur.
    private var brandText: Color {
        Color.onCard(appearance.colorHex) == .white ? brandColor : paperInk
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 8) {
            logo(size: compact ? 26 : 34)
            Text(ticket.brand.uppercased())
                .font(.system(size: compact ? 12 : 14, weight: .heavy, design: .rounded))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if appearance.tempUntil != nil { Image(systemName: "clock.fill").font(.caption2) }
            if appearance.isShared { Image(systemName: "person.2.fill").font(.caption2) }
            if appearance.isFavorite { Image(systemName: "star.fill").font(.caption2) }
            if appearance.isLocked { Image(systemName: "lock.fill").font(.caption2) }
            HStack(spacing: 3) {
                Image(systemName: CardKind.ticket.symbol).imageScale(.small)
                Text("Ticket")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(label)
        }
    }

    /// Logo van het evenement; zonder logo de initialen in de merkkleur.
    @ViewBuilder private func logo(size: CGFloat) -> some View {
        if let data = appearance.logoData {
            StoreLogoMark(data: data, style: appearance.logoStyle, height: size, maxWidth: size * 3.2, alignment: .leading)
        } else {
            Text(initials)
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .frame(width: size, height: size)
                .background(ink.opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        }
    }

    private var initials: String {
        let words = ticket.brand.split(separator: " ").prefix(2)
        let text = words.compactMap(\.first).map(String.init).joined().uppercased()
        return text.isEmpty ? "T" : text
    }

    @ViewBuilder private func typePill(small: Bool) -> some View {
        if let type = ticket.type {
            HStack(spacing: 6) {
                Text(type).font(.system(size: small ? 11 : 14, weight: .bold, design: .rounded))
                if let note = ticket.note {
                    Text(note).font(.system(size: small ? 10 : 12, weight: .medium, design: .rounded)).opacity(0.8)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, small ? 8 : 12)
            .padding(.vertical, small ? 3 : 5)
            .background(ink.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(ink.opacity(0.3), lineWidth: 1))
        }
    }

    private var fieldsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                if let d = ticket.dateText { field("DATUM", d) }
                if let t = ticket.timeText { field(timeLabel, t) }
                if let doors = ticket.doorsText { field("DEUREN", doors) }
                Spacer(minLength: 0)
            }
            if let holder = ticket.holder {
                HStack(alignment: .top, spacing: 16) {
                    field("NAAM", holder)
                    Spacer(minLength: 0)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                if let p = ticket.place { field("LOCATIE", p) }
                if let s = ticket.seat { field("PLAATS", s) }
                Spacer(minLength: 0)
            }
        }
    }

    /// "TIJD" bij een ticket van een zaak (begin – eind), anders "TOEGANG".
    private var timeLabel: LocalizedStringKey { ticket.isBusiness ? "TIJD" : "TOEGANG" }

    /// Geannuleerd, gebruikt of wachtlijst (ticket van een zaak), duidelijk in beeld.
    @ViewBuilder private func statusBadge(small: Bool) -> some View {
        if let style = statusStyle {
            Text(style.0)
                .font(.system(size: small ? 10 : 12, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .lineLimit(1)
                .padding(.horizontal, small ? 7 : 10)
                .padding(.vertical, small ? 3 : 5)
                .background(style.1, in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private var statusStyle: (String, Color)? {
        switch ticket.status {
        case "cancelled": (String(localized: "GEANNULEERD"), Color(hex: "#D64535"))
        case "checked_in", "used": (String(localized: "GEBRUIKT"), Color(hex: "#5B6170"))
        case "waitlist": (String(localized: "WACHTLIJST"), Color(hex: "#C98A12"))
        default: nil
        }
    }

    private func field(_ title: LocalizedStringKey, _ value: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: small ? 8 : 10, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(label)
            Text(value)
                .font(.system(size: small ? 11 : 16, weight: .semibold, design: .rounded))
                .lineLimit(small ? 1 : 2)
                .minimumScaleFactor(0.7)
        }
    }

    /// De code van de bezoeker (altijd zwart op wit), of waarom hij er niet staat.
    @ViewBuilder private func codeArea(compact: Bool) -> some View {
        if appearance.tempExpired {
            notice(appearance.tempRevoked ? "Delen gestopt" : "Verlopen", symbol: "clock.badge.xmark")
        } else if ticket.status == "cancelled" {
            notice("Geannuleerd door de organisator", symbol: "xmark.octagon.fill")
        } else if ticket.status == "waitlist" {
            notice("Je staat op de wachtlijst", symbol: "hourglass")
        } else if appearance.isLocked && !revealed {
            notice("Afgeschermd", symbol: "lock.fill")
        } else if appearance.number.isEmpty {
            notice("Geen code", symbol: "qrcode")
        } else if appearance.protectCode, let codeShield {
            codeShield(AnyView(code(compact: compact)))
        } else if ticket.status == "checked_in" || ticket.status == "used" {
            // al gescand: code blijft zichtbaar (voor de zaak), maar duidelijk als gebruikt
            code(compact: compact)
                .opacity(0.35)
                .overlay {
                    Text("GEBRUIKT")
                        .font(.system(size: compact ? 11 : 18, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(hex: "#5B6170"), in: Capsule())
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-12))
                }
        } else {
            code(compact: compact)
        }
    }

    private func code(compact: Bool) -> some View {
        VStack(spacing: compact ? 2 : 6) {
            BarcodeView(value: appearance.number, format: appearance.format, codeImage: appearance.codeImage)
                .aspectRatio(appearance.format.isLinear ? 2.6 : 1, contentMode: .fit)
            if !compact {
                Text(appearance.groupedNumber)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(compact ? 6 : 12)
        .background(.white, in: RoundedRectangle(cornerRadius: compact ? 8 : 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: compact ? 8 : 14, style: .continuous).strokeBorder(.black.opacity(0.08)))
    }

    private func notice(_ text: LocalizedStringKey, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3)
            Text(text).font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(paperInk.opacity(0.7))
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(paperInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actionButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.onCard(appearance.colorHex))
        .background(brandColor, in: Capsule())
    }

    private var accessibilityText: String {
        var parts = [ticket.title, String(localized: "ticket")]
        if let type = ticket.type { parts.append(type) }
        if let note = ticket.note { parts.append(note) }
        if let d = ticket.dateText { parts.append(d) }
        if let t = ticket.timeText { parts.append(String(localized: "toegang \(t)")) }
        if let p = ticket.place { parts.append(p) }
        if let h = ticket.holder { parts.append(h) }
        if let status = statusStyle?.0 { parts.append(status.lowercased()) }
        if layout != .front {
            if appearance.isLocked && !revealed { parts.append(String(localized: "code afgeschermd")) }
            else if !appearance.number.isEmpty { parts.append(String(localized: "\(appearance.format.displayName)-code")) }
        }
        return parts.joined(separator: ", ")
    }
}

private struct TicketHeadKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Afgeronde rechthoek met twee halve uitsparingen aan de zijkanten op hoogte `notchY`, zoals een ticket.
/// Gebruik met `.clipShape(TicketShape(...), style: FillStyle(eoFill: true))`.
struct TicketShape: Shape {
    var notchY: CGFloat
    var cornerRadius: CGFloat = 20
    var notchRadius: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        guard notchY > cornerRadius + notchRadius, notchY < rect.height - cornerRadius - notchRadius else { return path }
        let y = rect.minY + notchY
        path.addEllipse(in: CGRect(x: rect.minX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        path.addEllipse(in: CGRect(x: rect.maxX - notchRadius, y: y - notchRadius, width: notchRadius * 2, height: notchRadius * 2))
        return path   // met FillStyle(eoFill: true) knippen, dan zijn de rondjes uitsparingen
    }
}

/// De golvende onderrand van de kop: bovenaan vol, onderaan golven.
struct Wave: Shape {
    var waves: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.minY + rect.height * 0.45
        let amp = rect.height * 0.4
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: mid))
        let steps = 80
        for i in stride(from: steps, through: 0, by: -1) {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
            let y = mid + amp * sin(CGFloat(i) / CGFloat(steps) * waves * 2 * .pi)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.closeSubpath()
        return p
    }
}

/// Rechte lijn (gestreept getekend) als perforatie tussen kop en strookje.
private struct Perforation: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

#Preview("Ticket – licht") {
    let a: CardAppearance = {
        var a = CardAppearance(storeName: "Drakenboot – KIDS Early Bird", number: "PASR-DEMO-2027", format: .qr,
                               colorHex: "#1FB5B0", kind: .ticket)
        var e = TicketEvent(json: ["event": "Drakenboot 2027", "brand": "Drakenboot", "date": "2027-06-18", "doors": "17:00",
                                   "ends": "01:00", "venue": "Zwitsalpark", "city": "Apeldoorn", "ticket_type": "KIDS Early Bird",
                                   "ticket_note": "t/m 14 jaar", "info_url": "https://www.drakenboot.nl/tickets"])
        e?.textHex = "#FFFFFF"
        a.ticket = TicketInfo.resolve(name: a.storeName, templateID: nil, details: CardDetails(), event: e)
        return a
    }()
    ScrollView {
        VStack(spacing: 24) {
            TicketFaceView(appearance: a, layout: .front).aspectRatio(Brand.cardAspect, contentMode: .fit)
            TicketFaceView(appearance: a, layout: .code).aspectRatio(Brand.cardAspect, contentMode: .fit)
            TicketFaceView(appearance: a, demo: true)
        }
        .padding()
    }
}
