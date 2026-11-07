import Foundation
import Vision
import CoreGraphics
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Reads barcodes and text from a photo or screenshot, entirely on the device.
enum ImageCodeReader {
    struct Result {
        var payload: String
        var format: BarcodeFormat
        var recognizedText: String
        var template: StoreTemplate?
    }

    static func read(_ data: Data) async -> Result? {
        guard let cgImage = cgImage(from: data) else { return nil }
        return await read(cgImage)
    }

    /// Alleen de barcodes (snel), voor elk beeld uit een schermopname.
    nonisolated static func barcodes(in cgImage: CGImage) -> [(payload: String, format: BarcodeFormat)] {
        let request = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? [])
            .filter { $0.payloadStringValue?.isEmpty == false }
            .sorted { area($0.boundingBox) > area($1.boundingBox) }
            .map { ($0.payloadStringValue!, format(for: $0.symbology, payload: $0.payloadStringValue!)) }
    }

    static func read(_ cgImage: CGImage) async -> Result? {
        await Task.detached(priority: .userInitiated) { () -> Result? in
            let barcodes = VNDetectBarcodesRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.recognitionLanguages = ["nl-NL", "en-US", "de-DE", "fr-FR"]
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([barcodes, text])

            let best = (barcodes.results ?? [])
                .filter { $0.payloadStringValue?.isEmpty == false }
                .max { area($0.boundingBox) < area($1.boundingBox) }
            guard let best, let payload = best.payloadStringValue else { return nil }

            let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let joined = lines.joined(separator: "\n")
            return Result(payload: payload, format: format(for: best.symbology, payload: payload),
                          recognizedText: joined, template: StoreTemplates.match(in: joined))
        }.value
    }

    static func format(for symbology: VNBarcodeSymbology, payload: String) -> BarcodeFormat {
        switch symbology {
        case .ean13: return payload.count == 13 && payload.hasPrefix("0") ? .upcA : .ean13
        case .ean8: return .ean8
        case .upce: return .code128
        case .code128, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited: return .code128
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum, .code93, .code93i: return .code39
        case .itf14, .i2of5, .i2of5Checksum: return .itf
        case .qr, .microQR: return .qr
        case .pdf417, .microPDF417: return .pdf417
        case .aztec: return .aztec
        default: return BarcodeFormat.guess(for: payload)
        }
    }

    nonisolated private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    private static func cgImage(from data: Data) -> CGImage? {
        #if canImport(UIKit)
        return UIImage(data: data)?.cgImage
        #else
        guard let image = NSImage(data: data) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}
