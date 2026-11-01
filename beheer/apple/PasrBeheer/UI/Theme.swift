import SwiftUI

/// Kleuren en bouwstenen van PasrBeheer (zelfde kleuren als Pasr en beheer.pasr.nl).
enum Theme {
    static let bg = Color(hex: 0x0A0B10)
    static let card = Color(hex: 0x15171F)
    static let card2 = Color(hex: 0x1C1F29)
    static let line = Color(hex: 0x262A37)
    static let muted = Color(hex: 0x9A98B3)
    static let iris = Color(hex: 0x6A5CFF)
    static let iris2 = Color(hex: 0x8A7FFF)
    static let coral = Color(hex: 0xFF6B57)
    static let mint = Color(hex: 0x2ED3A6)
    static let amber = Color(hex: 0xFFB547)
    static let sky = Color(hex: 0x4FB3FF)

    static func color(_ m: Metric) -> Color {
        switch m {
        case .accounts: iris2
        case .signups: iris
        case .confirmed: mint
        case .deleted: coral
        case .cards: Color(hex: 0xFF8A78)
        case .wallet: sky
        case .bots: amber
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Woordmerk "pasr BEHEER" met het app-icoon.
struct BeheerLogo: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.4) {
            Image("Logo")
                .resizable()
                .frame(width: size * 1.4, height: size * 1.4)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.36, style: .continuous))
            Text("pasr")
                .font(.system(size: size, weight: .heavy, design: .default))
                .tracking(-size * 0.03)
            Text("BEHEER")
                .font(.system(size: max(9, size * 0.42), weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .overlay(Capsule().stroke(Theme.line))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PasrBeheer")
    }
}

/// Kaart met donkere achtergrond en rand.
struct CardBox<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
    }
}

/// Kerncijfer met gekleurde streep links.
struct KPITile: View {
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 26, weight: .heavy)).monospacedDigit().contentTransition(.numericText())
            Text(detail).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .padding(.vertical, 14).padding(.leading, 16).padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, style: .continuous)
                .fill(color).frame(width: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
        .accessibilityElement(children: .combine)
    }
}

/// Balk met label en aantal (verdelingen).
struct DistRow: View {
    let label: String
    let value: Int
    let total: Int
    let max: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Fmt.n(value)) · \(total > 0 ? Int((Double(value) / Double(total) * 100).rounded()) : 0)%")
                    .foregroundStyle(Theme.muted).monospacedDigit()
            }
            .font(.subheadline)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.card2)
                    Capsule().fill(color).frame(width: max > 0 ? geo.size.width * CGFloat(value) / CGFloat(max) : 0)
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .combine)
    }
}
