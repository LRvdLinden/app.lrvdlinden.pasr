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

/// De vakjes van een stempelkaart: gevuld met een vinkje, leeg als rondje; het laatste lege vakje is de beloning.
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
            Circle().fill(ink)
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.45, weight: .heavy))
                        .foregroundStyle(ink == .white ? Color.black.opacity(0.75) : Color.white)
                }
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
