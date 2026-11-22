import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Hulpjes voor zakelijk 1.1 (ondernemers en stempelkaarten aanmaken): QR-codes, kopiëren, afdrukken en de stempelkaart
/// zoals op pasr.nl/zakelijk. Zonder UIKit/AppKit waar het kan, zodat iPhone, iPad en Mac gelijk werken.
enum QRCode {
    /// Scherpe QR-code (zwart op wit, marge van 4 modules) van ongeveer `side` pixels.
    static func image(_ text: String, side: Int = 600) -> CGImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let modules = out.extent.width
        let scale = max(1, (CGFloat(side) / (modules + 8)).rounded(.down))
        let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let margin = 4 * scale
        let white = CIImage(color: .white).cropped(to: CGRect(x: -margin, y: -margin, width: scaled.extent.width + 2 * margin,
                                                              height: scaled.extent.height + 2 * margin))
        let full = scaled.composited(over: white)
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(full, from: full.extent)
    }

    static func png(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// PNG in een tijdelijk bestand, om te delen of te bewaren (ShareLink).
    static func pngFile(_ text: String, name: String) -> URL? {
        guard let img = image(text, side: 1000), let data = png(img) else { return nil }
        let safe = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pasr-\(safe).png")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Een QR-code afdrukken (met titel en de code als tekst eronder).
enum QRPrint {
    @MainActor
    static func print(_ text: String, title: String, caption: String) {
        guard let cg = QRCode.image(text, side: 1200) else { return }
        #if canImport(UIKit)
        let size = CGSize(width: 1240, height: 1754) // A4 bij 150 dpi
        let page = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
            let para = NSMutableParagraphStyle(); para.alignment = .center
            (title as NSString).draw(in: CGRect(x: 60, y: 120, width: size.width - 120, height: 120),
                                     withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.black, .paragraphStyle: para])
            UIImage(cgImage: cg).draw(in: CGRect(x: 220, y: 300, width: 800, height: 800))
            (caption as NSString).draw(in: CGRect(x: 60, y: 1150, width: size.width - 120, height: 300),
                                       withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 44, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: para])
        }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = title
        let c = UIPrintInteractionController.shared
        c.printInfo = info
        c.printingItem = page
        c.present(animated: true)
        #else
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .centerX
        view.spacing = 18
        let t = NSTextField(labelWithString: title); t.font = .boldSystemFont(ofSize: 20)
        let iv = NSImageView(image: NSImage(cgImage: cg, size: NSSize(width: 360, height: 360)))
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.widthAnchor.constraint(equalToConstant: 360).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 360).isActive = true
        let c = NSTextField(labelWithString: caption); c.font = .monospacedSystemFont(ofSize: 18, weight: .bold)
        view.addArrangedSubview(t); view.addArrangedSubview(iv); view.addArrangedSubview(c)
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 520)
        NSPrintOperation(view: view).run()
        #endif
    }
}

/// QR-code als afbeelding in SwiftUI.
struct QRView: View {
    let text: String
    var size: CGFloat = 150

    var body: some View {
        if let cg = QRCode.image(text, side: Int(size * 3)) {
            Image(decorative: cg, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(Text("QR-code"))
        }
    }
}

/// De stempelkaart zoals de klant hem ziet (pasr.nl/zakelijk, Pasr): kleurverloop, logo of initialen, stempelvakjes, beloning.
struct StampCardPreview: View {
    let name: String
    let business: String
    let city: String?
    let logo: String?
    let color: String
    let textColor: String?
    let total: Int
    let count: Int

    private var ink: Bool {
        if textColor?.uppercased() == "#000000" { return true }
        if textColor?.uppercased() == "#FFFFFF" { return false }
        return LogoColor.isLight(color)
    }
    private var fg: Color { ink ? Color(hex: 0x17162A) : .white }
    private var shown: Int { count > 0 && count % total == 0 ? total : count % max(total, 1) }
    private var cols: Int { total <= 5 ? total : total <= 10 ? 5 : total <= 12 ? 6 : total <= 21 ? 7 : 8 }
    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        let base = Color(hexString: color)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(logo == nil ? Color.white.opacity(0.22) : .white)
                    .frame(width: 38, height: 38)
                    .overlay {
                        CachedImage(key: "sc|\(logo?.count ?? 0)|\(logo?.suffix(24) ?? "")", base64: logo, maxPixel: 120) { img in
                            if let img { Image(decorative: img, scale: 1).resizable().scaledToFit() }
                            else { Text(initials.isEmpty ? "?" : initials).font(.system(size: 14, weight: .heavy)).foregroundStyle(fg) }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name.isEmpty ? String(localized: "Naam van de kaart") : name).font(.system(size: 18, weight: .bold)).lineLimit(1)
                    Text([business, city ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption.weight(.semibold)).opacity(0.8).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("Stempelkaart").font(.caption.weight(.bold)).opacity(0.8)
            }
            Spacer(minLength: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: max(cols, 1)), spacing: 6) {
                ForEach(0..<max(total, 1), id: \.self) { i in
                    let on = i < shown, last = i == total - 1
                    ZStack {
                        if on {
                            Circle().fill(ink ? Color(hex: 0x17162A) : .white)
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(ink ? .white : base)
                        } else {
                            Circle().strokeBorder(fg.opacity(ink ? 0.35 : 0.55), style: StrokeStyle(lineWidth: 2, dash: last ? [] : [4, 3]))
                            if last { Image(systemName: "gift").font(.system(size: 12, weight: .semibold)).foregroundStyle(fg.opacity(0.85)) }
                        }
                    }
                    .frame(maxWidth: 34, maxHeight: 34)
                    .aspectRatio(1, contentMode: .fit)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text(rewardText).lineLimit(1)
                Spacer()
                Text(count >= total ? String(localized: "Beloning klaar") : String(format: String(localized: "%lld te gaan"), total - shown))
                    .opacity(0.85)
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(fg)
        .padding(16)
        .aspectRatio(1.586, contentMode: .fit)
        .background(
            LinearGradient(colors: [base.blend(.white, 0.16), base, base.blend(.black, 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
        .frame(maxWidth: 400)
        .accessibilityElement(children: .combine)
    }

    private var rewardText: String { rewardLabel.isEmpty ? String(localized: "Beloning") : rewardLabel }
    private var rewardLabel: String { _reward }
    private let _reward: String

    init(name: String, business: String, city: String?, logo: String?, color: String, textColor: String?, total: Int, count: Int, reward: String) {
        self.name = name; self.business = business; self.city = city; self.logo = logo; self.color = color
        self.textColor = textColor; self.total = min(max(total, 2), 30); self.count = count; self._reward = reward
    }
}

extension Color {
    /// Mengen zonder iOS 18 (Color.mix bestaat pas vanaf iOS 18 / macOS 15).
    func blend(_ other: Color, _ part: Double) -> Color {
        let a = resolve(in: EnvironmentValues()), b = other.resolve(in: EnvironmentValues())
        let p = Float(part)
        return Color(red: Double(a.red + (b.red - a.red) * p), green: Double(a.green + (b.green - a.green) * p),
                     blue: Double(a.blue + (b.blue - a.blue) * p))
    }
}
