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

    var body: some View {
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
        .accessibilityElement(children: .combine)
    }

    /// "€ 25,00 · geldig tot 10 dec 2026"; bij een tijdelijke kaart "Gedeeld tot …" of "Verlopen".
    private var voucherInfo: String? {
        if let until = appearance.tempUntil {
            if appearance.tempRevoked { return String(localized: "Delen gestopt") }
            if appearance.tempExpired { return String(localized: "Verlopen op \(until.formatted(date: .abbreviated, time: .shortened))") }
            return String(localized: "Gedeeld tot \(until.formatted(date: .abbreviated, time: .shortened))")
        }
        guard appearance.kind == .voucher else { return nil }
        var parts: [String] = []
        if let balance = appearance.balanceText { parts.append(balance) }
        if let expires = appearance.expiresAt {
            parts.append(String(localized: "geldig tot \(expires.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Front side: the number in print, like on the real card.
    private var frontFooter: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appearance.kind == .voucher ? String(localized: "Kaartnummer") : String(localized: "Nummer"))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .opacity(0.7)
                Text(appearance.isLocked || appearance.tempExpired ? "•••• ••••" : appearance.groupedNumber)
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

    /// White panel with the code, filling the lower part of the card.
    private var codePanel: some View {
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
            Text(appearance.kind.displayName)
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
