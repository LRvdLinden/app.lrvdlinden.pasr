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
                                if i < filled {
                                    PasrStampShape().fill(color, style: FillStyle(eoFill: true)).padding(1)
                                } else {
                                    Circle().strokeBorder(color.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    if i == total - 1 {
                                        Image(systemName: "gift").font(.system(size: 12, weight: .semibold)).opacity(0.7)
                                    }
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
