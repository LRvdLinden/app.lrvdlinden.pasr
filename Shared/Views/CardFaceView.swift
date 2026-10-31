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

    init(storeName: String, number: String, format: BarcodeFormat, colorHex: String, kind: CardKind,
         isFavorite: Bool = false, logoData: Data? = nil, codeImage: Data? = nil,
         balance: Double? = nil, currencyCode: String? = nil, expiresAt: Date? = nil) {
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
    }

    init(_ card: Card) {
        self.init(storeName: card.storeName, number: card.number, format: card.format, colorHex: card.colorHex,
                  kind: card.kind, isFavorite: card.isFavorite, logoData: card.logoData, codeImage: card.codeImage,
                  balance: card.balance, currencyCode: card.currencyCode, expiresAt: card.expiresAt)
    }

    var displayName: String { storeName.isEmpty ? String(localized: "New card") : storeName }

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

/// A card drawn like a pass in Apple Wallet. `expanded` adds the code panel.
struct CardFaceView: View {
    let appearance: CardAppearance
    var expanded = false
    var cornerRadius: CGFloat = 20

    private var ink: Color { Color.onCard(appearance.colorHex) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 12)
                if expanded { codePanel.transition(.opacity.combined(with: .scale(scale: 0.96))) }
                footer
            }
            .padding(16)
        }
        .foregroundStyle(ink)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var background: some View {
        let hex = appearance.colorHex
        return ZStack {
            LinearGradient(colors: [Color.shade(hex, by: 0.14), Color(hex: hex), Color.shade(hex, by: -0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft rings, a quiet nod to the Pasr mark.
            GeometryReader { geo in
                let size = geo.size
                Circle()
                    .stroke(.white.opacity(0.07), lineWidth: size.width * 0.09)
                    .frame(width: size.width * 0.9)
                    .position(x: size.width * 0.98, y: size.height * 0.1)
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: size.width * 0.55)
                    .position(x: size.width * 0.05, y: size.height * 1.05)
            }
            LinearGradient(colors: [.white.opacity(0.16), .clear, .clear],
                           startPoint: .topLeading, endPoint: .center)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            logo
            Text(appearance.displayName)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if appearance.isFavorite {
                Image(systemName: "star.fill").font(.caption).opacity(0.85)
            }
            Text(appearance.kind.displayName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .opacity(0.72)
        }
        .frame(height: 32)
    }

    @ViewBuilder private var logo: some View {
        if let data = appearance.logoData, let image = Image(data: data) {
            image.resizable().scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            Text(appearance.monogram)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 32, height: 32)
                .background(ink.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var codePanel: some View {
        VStack(spacing: 8) {
            BarcodeView(value: appearance.number, format: appearance.format, codeImage: appearance.codeImage)
                .frame(height: appearance.format.isLinear ? 96 : 168)
                .frame(maxWidth: appearance.format.isLinear ? .infinity : 168)
            Text(appearance.groupedNumber)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(.black.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            if appearance.kind == .voucher, let balance = appearance.balanceText {
                field(label: String(localized: "Balance"), value: balance)
            } else if !expanded {
                field(label: String(localized: "Number"), value: appearance.groupedNumber, mono: true)
            }
            Spacer()
            if let expires = appearance.expiresAt {
                field(label: String(localized: "Valid until"),
                      value: expires.formatted(date: .abbreviated, time: .omitted), trailing: true)
            }
        }
    }

    private func field(label: String, value: String, mono: Bool = false, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.6)
                .opacity(0.7)
            Text(value)
                .font(mono ? .system(.subheadline, design: .monospaced).weight(.medium)
                           : .system(.title3, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
