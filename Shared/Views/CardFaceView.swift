import SwiftUI

/// What a card looks like; a value type so the editor can preview unsaved changes.
struct CardAppearance: Equatable {
    var storeName: String
    var number: String
    var format: BarcodeFormat
    var colorHex: String
    var kind: CardKind
    var isFavorite = false
    var logoData: Data?
    var codeImage: Data?
    var balance: Double?
    var currencyCode: String?
    var expiresAt: Date?
    var isLocked = false
    /// How to draw a store logo that came with the app or from the website (nil for own logos).
    var logoStyle: StoreLogoStyle?
    /// In een gedeelde Pasr: klein personen-icoon in de kop.
    var isShared = false
    /// Tijdelijk met mij gedeeld: tot wanneer (nil = gewone kaart) en of de deler eerder stopte.
    var tempUntil: Date?
    var tempRevoked = false
    /// Voorbij het einde: de code wordt niet meer getoond.
    var tempExpired: Bool { tempUntil.map { tempRevoked || $0 <= .now } ?? false }
    /// Code beschermen tegen schermafbeeldingen (tijdelijke kaarten altijd, eigen kaarten met de instelling).
    var protectCode = false
    /// Gegevens van ticket, abonnement of kortingscode.
    var details = CardDetails()
    /// Kortingscode als tekst in plaats van een barcode.
    var codeAsText = false
    /// Eigen voorkant (foto, al op kaartformaat bijgesneden).
    var cover: Data?
    /// Kaartontwerp van de winkel uit het beheer (alleen cadeaukaarten); een eigen voorkant gaat voor.
    var storeCover: Data?
    /// Ticket: evenement, soort, datum, toegang en locatie (uit de catalogus en de kaart); nil = alleen uit naam en details.
    var ticket: TicketInfo?

    init(storeName: String, number: String, format: BarcodeFormat, colorHex: String, kind: CardKind,
         isFavorite: Bool = false, logoData: Data? = nil, codeImage: Data? = nil,
         balance: Double? = nil, currencyCode: String? = nil, expiresAt: Date? = nil, isLocked: Bool = false,
         logoStyle: StoreLogoStyle? = nil) {
        self.storeName = storeName
        self.number = number
        self.format = format
        self.colorHex = colorHex
        self.kind = kind
        self.isFavorite = isFavorite
        self.logoData = logoData
        self.codeImage = codeImage
        self.balance = balance
        self.currencyCode = currencyCode
        self.expiresAt = expiresAt
        self.isLocked = isLocked
        self.logoStyle = logoStyle
    }

    init(_ card: Card) {
        self.init(storeName: card.storeName, number: card.number, format: card.format, colorHex: card.colorHex,
                  kind: card.kind, isFavorite: card.isFavorite, logoData: card.logoData, codeImage: card.codeImage,
                  balance: card.balance, currencyCode: card.currencyCode, expiresAt: card.expiresAt,
                  isLocked: card.isLocked,
                  logoStyle: card.logoFromWebsite ? StoreLogoStyles.style(for: card.logoDomain) : nil)
        isShared = card.groupID != nil
        if card.isTemporary {
            tempUntil = card.sharedUntil ?? .distantPast
            tempRevoked = card.shareRevoked
        }
        protectCode = card.isTemporary || UserDefaults.standard.bool(forKey: "pasr.screenshotShield")
        details = card.details
        codeAsText = card.showsCodeAsText
        cover = card.coverPhoto
        storeCover = card.storeCover
        if card.kind == .ticket { ticket = card.ticketInfo }
    }

    /// Kopie met de gegevens van ticket, abonnement of kortingscode.
    func with(details: CardDetails, codeAsText: Bool) -> CardAppearance {
        var copy = self
        copy.details = details
        copy.codeAsText = codeAsText
        return copy
    }

    var displayName: String { storeName.isEmpty ? String(localized: "Nieuwe kaart") : storeName }

    /// The number in groups of four, as printed on most cards.
    var groupedNumber: String {
        let compact = number.replacingOccurrences(of: " ", with: "")
        guard compact.count > 8, compact.allSatisfy(\.isNumber) else { return number }
        return stride(from: 0, to: compact.count, by: 4).map { start in
            let s = compact.index(compact.startIndex, offsetBy: start)
            let e = compact.index(s, offsetBy: min(4, compact.count - start))
            return String(compact[s..<e])
        }.joined(separator: " ")
    }

    var balanceText: String? {
        guard let balance else { return nil }
        return balance.formatted(.currency(code: currencyCode ?? Locale.current.currency?.identifier ?? "EUR"))
    }

    /// De regel onder de kop: tegoed en geldigheid (voucher), geldigheid (kortingscode), datum en plaats (ticket),
    /// kosten en verlengdatum (abonnement).
    var infoLine: String? {
        var parts: [String] = []
        switch kind {
        case .loyalty:
            return nil
        case .voucher, .code:
            if kind == .voucher, let balance = balanceText { parts.append(balance) }
            if let expiresAt {
                parts.append(String(localized: "geldig tot \(expiresAt.formatted(date: .abbreviated, time: .omitted))"))
            }
        case .ticket:
            if let date = details.eventDate { parts.append(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) }
            if let venue = details.venue, !venue.isEmpty { parts.append(venue) }
        case .subscription:
            if let cost = details.cost {
                parts.append(cost.formatted(.currency(code: currencyCode ?? "EUR")) + " " + details.periodValue.title)
            }
            if let renews = details.renewsAt {
                parts.append(String(localized: "verlengt \(renews.formatted(.dateTime.day().month(.abbreviated)))"))
            }
        case .stamps:
            parts.append(details.stampsProgressText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var monogram: String {
        let words = displayName.split(separator: " ").prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// A card drawn like a pass in Apple Wallet. With `showsCode` it is the back, with the barcode or QR code;
/// without it, the front with logo, name and number.
/// De app zet hier de bescherming tegen schermafbeeldingen in (ScreenShield); Watch en widgets niet.
private struct CodeShieldKey: EnvironmentKey {
    static let defaultValue: ((AnyView) -> AnyView)? = nil
}

extension EnvironmentValues {
    var codeShield: ((AnyView) -> AnyView)? {
        get { self[CodeShieldKey.self] }
        set { self[CodeShieldKey.self] = newValue }
    }
}

struct CardFaceView: View {
    @Environment(\.codeShield) private var codeShield
    let appearance: CardAppearance
    /// Off for tiny previews where a code would be unreadable anyway.
    var showsCode = true
    /// For a locked card: true once Face ID has confirmed it's you.
    var revealed = false
    var cornerRadius: CGFloat = 20

    private var ink: Color { Color.onCard(appearance.colorHex) }

    /// Wat VoiceOver voorleest: winkel, soort, gegevens, en op de achterkant of de code leesbaar is.
    private var accessibilityText: String {
        var parts = [appearance.displayName, appearance.kind.displayName]
        if appearance.isFavorite { parts.append(String(localized: "favoriet")) }
        if appearance.isShared { parts.append(String(localized: "gedeeld")) }
        if let info = voucherInfo { parts.append(info) }
        if appearance.kind == .stamps {
            parts.append(String(localized: "\(appearance.details.stampsCountValue) van \(appearance.details.stampsTotalValue) stempels"))
        }
        if showsCode {
            if appearance.tempExpired {
                parts.append(String(localized: "verlopen, de code wordt niet meer getoond"))
            } else if appearance.isLocked && !revealed {
                parts.append(String(localized: "code afgeschermd"))
            } else if appearance.number.isEmpty {
                parts.append(String(localized: "geen code"))
            } else if appearance.codeAsText {
                parts.append(String(localized: "code \(appearance.number)"))
            } else {
                parts.append(String(localized: "\(appearance.format.displayName)-code, nummer \(appearance.groupedNumber)"))
            }
        } else if !appearance.isLocked && !appearance.tempExpired && !appearance.number.isEmpty {
            parts.append(String(localized: "nummer \(appearance.groupedNumber)"))
        }
        return parts.joined(separator: ", ")
    }

    /// De voorkant is een eigen foto: die vult de hele kaart, met alleen een donkere rand onderaan voor het nummer.
    private var coverImage: Image? {
        guard !showsCode, let data = appearance.cover else { return nil }
        return Image(data: data)
    }

    /// Het kaartontwerp van de winkel (cadeaukaart), als er geen eigen voorkant is.
    private var storeCoverImage: Image? {
        guard !showsCode, appearance.cover == nil, appearance.kind == .voucher, let data = appearance.storeCover else { return nil }
        return Image(data: data)
    }

    var body: some View {
        if let coverImage {
            coverFront(coverImage)
        } else if appearance.kind == .ticket {
            // een ticket ziet eruit als een ticket (zoals eventTicket in Apple Wallet), niet als een klantenkaart
            TicketFaceView(appearance: appearance, layout: showsCode ? .code : .front, revealed: revealed,
                           cornerRadius: cornerRadius)
        } else if let storeCoverImage {
            storeCoverFront(storeCoverImage)
        } else {
            standardFace
        }
    }

    /// Voorkant met het echte kaartontwerp van de winkel: de afbeelding vult de kaart (afgeronde hoeken). Alleen wat
    /// er echt toe doet staat er klein overheen: favoriet/gedeeld/slot rechtsboven en het tegoed linksonder.
    private func storeCoverFront(_ image: Image) -> some View {
        ZStack {
            Color(hex: appearance.colorHex)
            image.resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 0) {
                let marks = appearance.tempUntil != nil || appearance.isShared || appearance.isFavorite || appearance.isLocked
                if marks {
                    HStack(spacing: 6) {
                        if appearance.tempUntil != nil { Image(systemName: "clock.fill") }
                        if appearance.isShared { Image(systemName: "person.2.fill") }
                        if appearance.isFavorite { Image(systemName: "star.fill") }
                        if appearance.isLocked { Image(systemName: "lock.fill") }
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Spacer(minLength: 0)
                if let info = voucherInfo {
                    Text(info)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                }
            }
            .padding(10)
            .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private func coverFront(_ image: Image) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: appearance.colorHex)
            image.resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if appearance.isShared { Image(systemName: "person.2.fill").font(.caption) }
                    if appearance.isFavorite { Image(systemName: "star.fill").font(.caption) }
                    Text(appearance.kind.displayName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(0.6)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.35), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer(minLength: 0)
                if let info = voucherInfo {
                    Text(info)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                }
                frontFooter
            }
            .padding(14)
            .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var standardFace: some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 8) {
                header
                if let info = voucherInfo {
                    Text(info)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .opacity(0.85)
                        .lineLimit(1)
                }
                if showsCode && appearance.tempExpired {
                    expiredPanel
                } else if showsCode && appearance.isLocked && !revealed {
                    lockedPanel
                } else if showsCode {
                    if appearance.protectCode, let codeShield {
                        codeShield(AnyView(codePanel))
                    } else {
                        codePanel
                    }
                } else if appearance.kind == .stamps {
                    StampGridView(total: appearance.details.stampsTotalValue, count: appearance.details.stampsCountValue,
                                  ink: ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                    frontFooter
                }
            }
            .padding(14)
        }
        .foregroundStyle(ink)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    /// "€ 25,00 · geldig tot 10 dec 2026"; bij een tijdelijke kaart "Gedeeld tot …" of "Verlopen".
    private var voucherInfo: String? {
        if let until = appearance.tempUntil {
            if appearance.tempRevoked { return String(localized: "Delen gestopt") }
            if appearance.tempExpired { return String(localized: "Verlopen op \(until.formatted(date: .abbreviated, time: .shortened))") }
            return String(localized: "Gedeeld tot \(until.formatted(date: .abbreviated, time: .shortened))")
        }
        return appearance.infoLine
    }

    /// Front side: the number in print, like on the real card.
    private var frontFooter: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appearance.kind == .loyalty ? String(localized: "Nummer") : appearance.kind.codeLabel)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .opacity(0.7)
                Text(appearance.isLocked || appearance.tempExpired ? "•••• ••••" : (appearance.number.isEmpty ? "–" : appearance.groupedNumber))
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
            Image(systemName: appearance.tempUntil != nil ? "clock.fill" : appearance.isLocked ? "lock.fill" : "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.semibold))
                .opacity(0.6)
        }
    }

    /// Tijdelijke kaart voorbij het einde: geen code meer, alleen de melding.
    private var expiredPanel: some View {
        VStack(spacing: 6) {
            Image(systemName: appearance.tempRevoked ? "hand.raised.fill" : "clock.badge.xmark").font(.title3)
            Text(appearance.tempRevoked ? "Delen gestopt" : "Verlopen")
                .font(.system(.caption, design: .rounded).weight(.semibold))
            Text("Deze tijdelijk gedeelde kaart werkt niet meer.")
                .font(.system(size: 10, design: .rounded))
                .opacity(0.8)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .opacity(0.85)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var lockedPanel: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill").font(.title3)
            Text("Afgeschermd").font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .opacity(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// White panel with the code, filling the lower part of the card. Een kortingscode als tekst; een abonnement zonder
    /// lidnummer krijgt zijn gegevens in plaats van een code.
    @ViewBuilder private var codePanel: some View {
        if appearance.number.isEmpty {
            noCodePanel
        } else if appearance.codeAsText {
            textCodePanel
        } else {
            barcodePanel
        }
    }

    private var textCodePanel: some View {
        VStack(spacing: 6) {
            Text(appearance.kind.codeLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.black.opacity(0.55))
            Text(appearance.number)
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .foregroundStyle(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var noCodePanel: some View {
        if appearance.kind == .stamps {
            StampGridView(total: appearance.details.stampsTotalValue, count: appearance.details.stampsCountValue, ink: ink)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            noCodeInfoPanel
        }
    }

    private var noCodeInfoPanel: some View {
        VStack(spacing: 6) {
            Image(systemName: appearance.kind.symbol).font(.title3)
            Text(appearance.infoLine ?? appearance.kind.displayName)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .opacity(0.85)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var barcodePanel: some View {
        VStack(spacing: 4) {
            BarcodeView(value: appearance.number, format: appearance.format, codeImage: appearance.codeImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(appearance.groupedNumber)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.black.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One flat brand colour, like a real card (and like SuperCards): no gradient, no decoration.
    private var background: some View {
        Color(hex: appearance.colorHex)
    }

    private var header: some View {
        HStack(spacing: 10) {
            logo
            // The logo says which store it is; the name only when there is no logo.
            if appearance.logoData == nil {
                Text(appearance.displayName)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if appearance.tempUntil != nil {
                Image(systemName: "clock.fill").font(.caption).opacity(0.85)
                    .accessibilityLabel(Text("Tijdelijk gedeeld"))
            }
            if appearance.isShared {
                Image(systemName: "person.2.fill").font(.caption).opacity(0.85)
                    .accessibilityLabel(Text("Gedeeld"))
            }
            if appearance.isFavorite {
                Image(systemName: "star.fill").font(.caption).opacity(0.85)
            }
            Label(appearance.kind.displayName, systemImage: appearance.kind.symbol)
                .labelStyle(KindLabelStyle())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .opacity(0.72)
        }
        .frame(height: 36)
    }

    @ViewBuilder private var logo: some View {
        if let data = appearance.logoData {
            StoreLogoMark(data: data, style: appearance.logoStyle, height: 38, maxWidth: 170, alignment: .leading)
        } else {
            Text(appearance.monogram)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 32, height: 32)
                .background(ink.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

/// Klein pictogram voor de soort, naast de naam (zo hangt de soort niet alleen van kleur of tekst af).
private struct KindLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// De vakjes van een stempelkaart: officiële Pasr-zegel bij gevuld, gestippeld rondje bij leeg.
/// Exacte vectorcontour van de aangeleverde Pasr-stempel; transparante uitsparingen
/// tonen automatisch de achtergrond-/merkkleur van de stempelkaart.
private struct PasrStampShape: Shape {
    private static let outline = "M54,4 L43,7 L34,11 L24,18 L14,29 L10,35 L4,49 L2,58 L2,75 L4,85 L8,95 L14,105 L23,115 L31,121 L49,129 L74,130 L85,127 L97,121 L106,114 L116,102 L123,87 L125,79 L125,74 L126,73 L125,53 L118,35 L111,25 L100,15 L90,9 L79,5Z M57,8 L63,11 L70,8 L75,12 L84,12 L90,18 L93,19 L97,18 L100,21 L101,26 L107,29 L110,32 L111,39 L118,45 L117,54 L122,63 L122,66 L119,70 L120,80 L116,85 L116,92 L110,97 L110,103 L108,105 L102,107 L100,110 L100,113 L98,115 L91,115 L84,122 L75,121 L68,125 L57,124 L53,121 L44,122 L39,116 L30,115 L28,113 L27,108 L18,103 L18,97 L11,91 L12,84 L7,78 L9,73 L9,68 L6,64 L6,61 L11,55 L10,46 L15,42 L17,38 L17,32 L25,28 L28,20 L37,19 L42,12 L51,13Z M56,17 L46,20 L38,24 L31,29 L23,38 L16,52 L14,62 L14,71 L18,87 L24,97 L31,105 L46,114 L53,116 L66,117 L81,114 L91,109 L103,98 L108,90 L107,89 L108,86 L111,83 L113,76 L113,67 L114,66 L113,65 L113,56 L107,41 L101,33 L93,26 L80,19 L72,17Z M93,101 L94,103 L91,105 L90,103Z M106,82 L107,85 L103,93 L96,100 L95,98 L101,91 L104,83Z M88,76 L65,107 L62,106 L49,96 L49,93 L53,89 L56,90 L62,95 L64,95 L81,72 L83,72Z M42,56 L47,62 L46,73 L41,78 L38,79 L33,78 L33,86 L31,88 L27,88 L25,86 L25,75 L24,74 L23,60 L27,58 L31,59 L34,56 L38,55Z M34,63 L32,65 L32,70 L33,72 L37,72 L39,70 L39,65 L38,63Z M65,51 L68,55 L69,69 L64,72 L61,71 L57,74 L50,73 L48,70 L48,65 L52,61 L56,59 L60,59 L60,57 L56,57 L51,60 L48,56 L52,52 L57,50Z M60,63 L56,65 L57,68 L60,67 L61,65Z M86,45 L87,48 L85,51 L78,51 L77,52 L87,54 L89,56 L89,62 L82,68 L72,68 L70,65 L74,61 L80,62 L82,60 L73,59 L70,56 L71,49 L77,45 L81,44Z M103,39 L104,40 L104,45 L98,51 L99,62 L96,64 L92,64 L90,54 L90,43 L95,41 L97,43 L101,39Z M87,30 L86,32 L83,32 L79,29 L72,27 L55,27 L43,32 L30,45 L28,44 L28,42 L31,38 L41,29 L49,25 L57,23 L71,23 L83,27Z"

    func path(in rect: CGRect) -> Path {
        var result = Path()
        for contour in Self.outline.split(separator: "M") {
            var started = false
            for pair in contour.split(whereSeparator: { $0 == "L" || $0 == "Z" || $0 == " " }) {
                let coords = pair.split(separator: ",")
                guard coords.count == 2, let x = Double(coords[0]), let y = Double(coords[1]) else { continue }
                let point = CGPoint(x: rect.minX + rect.width * CGFloat(x / 131.0),
                                    y: rect.minY + rect.height * CGFloat(y / 135.0))
                if started { result.addLine(to: point) } else { result.move(to: point); started = true }
            }
            if started { result.closeSubpath() }
        }
        return result
    }
}

struct StampGridView: View {
    let total: Int
    let count: Int
    var ink: Color = .white

    private var rows: Int { total <= 6 ? 1 : total <= 16 ? 2 : 3 }
    private var columns: Int { Int((Double(total) / Double(rows)).rounded(.up)) }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let side = max(6, min((geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns),
                                  (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows), 44))
            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < total { cell(index, side: side) } else { Color.clear.frame(width: side, height: side) }
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) van \(total) stempels"))
    }

    @ViewBuilder private func cell(_ index: Int, side: CGFloat) -> some View {
        if index < count {
            PasrStampShape()
                .fill(ink, style: FillStyle(eoFill: true))
                .frame(width: side, height: side)
        } else {
            Circle().strokeBorder(ink.opacity(0.55), style: StrokeStyle(lineWidth: max(1.2, side * 0.06), dash: [side * 0.12, side * 0.08]))
                .frame(width: side, height: side)
                .overlay {
                    if index == total - 1 {
                        Image(systemName: "gift.fill")
                            .font(.system(size: side * 0.42, weight: .semibold))
                            .foregroundStyle(ink.opacity(0.7))
                    }
                }
        }
    }
}
