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
                            // officiële Pasr-stempel: wit (of donker) zegel, uitsparingen tonen de merkkleur van de kaart
                            PasrStampShape().fill(fg, style: FillStyle(eoFill: true))
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

/// Exacte vectorcontour van de Pasr-stempel (gelijk aan Pasr en Pasr Zakelijk).
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
