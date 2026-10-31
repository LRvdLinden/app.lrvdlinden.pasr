import SwiftUI
#if !os(watchOS)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Draws a card's code: bars from `BarcodeEncoder`, or a 2D code via Core Image
/// (on watchOS from the PNG the iPhone rendered and synced).
struct BarcodeView: View {
    let value: String
    let format: BarcodeFormat
    var codeImage: Data? = nil

    var body: some View {
        if format.isLinear {
            if let code = try? BarcodeEncoder.encode(value, as: format) {
                LinearBarcodeShape(modules: code.modules)
                    .fill(Color.black)
                    .accessibilityLabel(Text("Barcode \(code.humanReadable)"))
            } else {
                invalid
            }
        } else {
            matrix
        }
    }

    @ViewBuilder private var matrix: some View {
        #if os(watchOS)
        if let codeImage, let image = Image(data: codeImage) {
            image.interpolation(.none).resizable().aspectRatio(contentMode: .fit)
        } else {
            invalid
        }
        #else
        if let cgImage = MatrixCodeRenderer.cgImage(for: value, format: format) {
            Image(decorative: cgImage, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityLabel(Text("\(format.displayName) code"))
        } else {
            invalid
        }
        #endif
    }

    private var invalid: some View {
        VStack(spacing: 4) {
            Image(systemName: "barcode.viewfinder").font(.title2)
            Text("Can't draw this code").font(.footnote.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bars as one shape, with a quiet zone of 10 modules on each side.
struct LinearBarcodeShape: Shape {
    let modules: [Bool]
    var quietZone = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let total = CGFloat(modules.count + quietZone * 2)
        let width = rect.width / total
        var index = 0
        while index < modules.count {
            guard modules[index] else { index += 1; continue }
            var end = index
            while end < modules.count, modules[end] { end += 1 }
            let x = rect.minX + CGFloat(quietZone + index) * width
            path.addRect(CGRect(x: x, y: rect.minY, width: CGFloat(end - index) * width, height: rect.height))
            index = end
        }
        return path
    }
}

#if !os(watchOS)

enum MatrixCodeRenderer {
    nonisolated(unsafe) private static let context = CIContext()
    nonisolated(unsafe) private static let cache = NSCache<NSString, CGImage>()

    static func cgImage(for value: String, format: BarcodeFormat) -> CGImage? {
        let key = "\(format.rawValue)|\(value)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = value.data(using: .isoLatin1) ?? value.data(using: .utf8) else { return nil }
        let output: CIImage?
        switch format {
        case .qr:
            let filter = CIFilter.qrCodeGenerator()
            filter.message = data
            filter.correctionLevel = "M"
            output = filter.outputImage
        case .pdf417:
            let filter = CIFilter.pdf417BarcodeGenerator()
            filter.message = data
            output = filter.outputImage
        case .aztec:
            let filter = CIFilter.aztecCodeGenerator()
            filter.message = data
            output = filter.outputImage
        default:
            output = nil
        }
        guard let output else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let image = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// PNG of a 2D code, stored on the card so the Watch can show it.
    static func pngData(for value: String, format: BarcodeFormat) -> Data? {
        guard !format.isLinear, let image = cgImage(for: value, format: format) else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: image).pngData()
        #else
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
        #endif
    }
}

extension Card {
    /// Keeps the synced PNG of a 2D code up to date for the Watch.
    func refreshCodeImage() {
        codeImage = format.isLinear ? nil : MatrixCodeRenderer.pngData(for: number, format: format)
    }
}
#endif
