import SwiftUI
import UIKit

/// Logo van de server (base64, PNG/JPEG) als afbeelding.
enum LogoImage {
    static func image(_ base64: String?) -> UIImage? {
        guard let base64, !base64.isEmpty else { return nil }
        let raw = base64.components(separatedBy: ",").last ?? base64
        guard let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }

    /// Verkleint tot hoogstens 256 px en maakt er base64 van (PNG, of JPEG als PNG te groot is), zoals het dashboard.
    static func encode(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 256
        let scale = min(maxSide / max(image.size.width, 1), maxSide / max(image.size.height, 1), 1)
        let size = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        if let png = small.pngData(), png.count <= 150_000 { return png.base64EncodedString() }
        for q in [0.85, 0.7, 0.5] {
            if let jpg = small.jpegData(compressionQuality: q), jpg.count <= 150_000 { return jpg.base64EncodedString() }
        }
        return nil
    }
}

/// Stempelkaart zoals de klant hem ziet: kleur, logo, naam, vakjes.
struct StampCardView: View {
    let name: String
    let business: String?
    let color: String
    let logo: String?
    let total: Int
    let filled: Int
    let reward: String
    var textColor: String? = nil

    private var fg: Color { textColor.map { Color(hex: $0) } ?? Color.onCard(color) }
    private var initial: String {
        let source = (business?.isEmpty == false ? business : nil) ?? name
        return source.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "P"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let image = LogoImage.image(logo) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(width: 38, height: 38)
                        .background(.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    // geen logo: de initiaal van de zaak
                    Text(verbatim: initial)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .frame(width: 38, height: 38)
                        .background(fg.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name.isEmpty ? "–" : name).font(.headline).lineLimit(1)
                    if let business, !business.isEmpty {
                        Text(verbatim: business).font(.caption).opacity(0.8).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(verbatim: "\(min(filled, total))/\(total)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
            StampGrid(total: total, filled: filled, color: fg)
            if !reward.isEmpty {
                Label { Text(verbatim: reward).lineLimit(1) } icon: { Image(systemName: "gift.fill") }
                    .font(.caption.weight(.semibold))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(fg)
        .padding(16)
        .background(
            LinearGradient(colors: [Color(hex: color), Color(hex: color).opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: String(localized: "%@: %lld van %lld stempels"), name, min(filled, total), total)))
    }
}

/// Vakjes van de stempelkaart (5 per rij tot 10, daarna 6 of meer).
struct StampGrid: View {
    let total: Int
    let filled: Int
    var color: Color = .white

    private var perRow: Int { total <= 10 ? 5 : (total <= 18 ? 6 : 8) }

    var body: some View {
        let rows = Int((Double(total) / Double(perRow)).rounded(.up))
        VStack(spacing: 8) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(0..<perRow, id: \.self) { c in
                        let i = r * perRow + c
                        if i < total {
                            ZStack {
                                Circle().strokeBorder(color.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: i < filled ? [] : [3, 3]))
                                if i < filled {
                                    Circle().fill(color.opacity(0.95)).padding(3)
                                    Image(systemName: i == total - 1 ? "gift.fill" : "checkmark")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(color == .white ? Color.black.opacity(0.75) : Color.white)
                                } else if i == total - 1 {
                                    Image(systemName: "gift").font(.system(size: 12, weight: .semibold)).opacity(0.7)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 40)
                            .transition(.scale.combined(with: .opacity))
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit).frame(maxWidth: 40)
                        }
                    }
                }
            }
        }
        .animation(.spring(duration: 0.35), value: filled)
    }
}
