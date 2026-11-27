import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import CoreImage.CIFilterBuiltins

/// Barcode als afbeelding: QR, Code 128 of EAN-13 (EAN-13 zelf getekend; Core Image kent hem niet).
enum Barcode {
    static func image(_ text: String, type: String) -> UIImage? {
        switch type {
        case "qr": return QRCode.image(text, scale: 8)
        case "ean13": return ean13(text) ?? code128(text)
        default: return code128(text)
        }
    }

    static func code128(_ text: String) -> UIImage? {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(text.utf8)
        filter.quietSpace = 4
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 4, y: 4)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static let l = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let g = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
    private static let r = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
    private static let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    static func ean13(_ text: String) -> UIImage? {
        let digits = text.compactMap { $0.wholeNumberValue }
        guard digits.count == 13 else { return nil }
        var bits = "101"
        let p = Array(parity[digits[0]])
        for i in 1...6 { bits += (p[i - 1] == "L" ? l : g)[digits[i]] }
        bits += "01010"
        for i in 7...12 { bits += r[digits[i]] }
        bits += "101"
        let module: CGFloat = 4, quiet: CGFloat = 9 * 4, height: CGFloat = 160
        let size = CGSize(width: CGFloat(bits.count) * module + quiet * 2, height: height)
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            for (i, bit) in bits.enumerated() where bit == "1" {
                ctx.fill(CGRect(x: quiet + CGFloat(i) * module, y: 0, width: module, height: height))
            }
        }
        #else
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        for (i, bit) in bits.enumerated() where bit == "1" {
            ctx.fill(CGRect(x: quiet + CGFloat(i) * module, y: 0, width: module, height: height))
        }
        return ctx.makeImage().map { NSImage(cgImage: $0) }
        #endif
    }
}

/// Klantenkaart zoals de klant hem ziet: naam, korting die nu geldt, spaarstand en barcode.
struct MemberCardPreview: View {
    let card: MemberCard
    let business: String
    var number: String?
    var memberName: String?

    private var fg: Color { Color.onCard(card.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                logo
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: card.name.isEmpty ? String(localized: "Naam van de kaart") : card.name)
                        .font(.headline).lineLimit(1)
                    Text(verbatim: business).font(.caption).opacity(0.8).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("KLANTENKAART").font(.caption2.weight(.heavy)).tracking(1).opacity(0.85)
            }
            if let line = discountLine {
                Label { Text(verbatim: line) } icon: { Image(systemName: "percent") }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(hex: card.color))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if card.goals.savingEnabled {
                HStack(spacing: 8) {
                    Text("Spaarstand").font(.caption.weight(.semibold))
                    ProgressView(value: 0.6).tint(fg)
                    Text(verbatim: "\(card.goals.savingTarget * 6 / 10)/\(card.goals.savingTarget)").font(.caption.weight(.bold)).monospacedDigit()
                }
            }
            barcode
            if let memberName {
                Text(String(format: String(localized: "Lid: %@"), memberName)).font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(fg)
        .padding(16)
        .background(Color(hex: card.color), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var discountLine: String? {
        if let d = card.discountNow {
            return String(format: String(localized: "Nu %@%% korting"), TKFormat.percent(d.percent))
        }
        if card.goals.fixedEnabled {
            return String(format: String(localized: "%@%% korting voor leden"), TKFormat.percent(card.goals.fixedPercent))
        }
        if let first = card.goals.periods.first {
            return String(format: String(localized: "%@%% korting"), TKFormat.percent(first.percent)) + " · " + first.summary
        }
        return nil
    }

    @ViewBuilder private var logo: some View {
        if let logo = card.logo, let image = LogoImage.image(logo) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            Text(verbatim: String(business.prefix(1)).uppercased())
                .font(.headline.weight(.heavy))
                .frame(width: 34, height: 34)
                .background(fg.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var barcode: some View {
        let text = number ?? card.sampleNumber
        return VStack(spacing: 4) {
            if let image = Barcode.image(text, type: card.barcodeType) {
                Image(uiImage: image).interpolation(.none).resizable()
                    .scaledToFit()
                    .frame(maxHeight: card.barcodeType == "qr" ? 130 : 70)
            }
            Text(verbatim: text).font(.caption.monospaced()).foregroundStyle(.black)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
