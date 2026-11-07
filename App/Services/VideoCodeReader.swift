import AVFoundation
import CoreGraphics
import CoreTransferable
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Kaarten uit een schermopname halen: je neemt je scherm op terwijl je in Klarna of een andere kaarten-app langs
/// je kaarten gaat, en Pasr leest elke barcode die voorbijkomt. Alles gebeurt op het apparaat.
enum VideoCodeReader {
    struct Found {
        var result: ImageCodeReader.Result
        var frame: Data?
    }

    /// Een video uit Foto's als bestand.
    struct Movie: Transferable {
        let url: URL
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
                let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
                let copy = FileManager.default.temporaryDirectory.appending(path: "pasr-import-\(UUID().uuidString).\(ext)")
                try FileManager.default.copyItem(at: received.file, to: copy)
                return Movie(url: copy)
            }
        }
    }

    /// Leest de video met ongeveer 3 beelden per seconde. Alleen bij een nieuwe barcode wordt ook de tekst gelezen
    /// (om de winkel te herkennen), dus een lange opname gaat toch snel. `progress` loopt van 0 tot 1.
    static func read(_ url: URL, existing: Set<String>, progress: @escaping @MainActor (Double) -> Void,
                     found: @escaping @MainActor (Found) -> Void) async {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1400, height: 1400)
        let tolerance = CMTime(value: 1, timescale: 10)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let step = 0.33
        let times = stride(from: 0.0, to: duration.seconds, by: step).map { CMTime(seconds: $0, preferredTimescale: 600) }
        var seen = existing
        var done = 0
        for await result in generator.images(for: times) {
            done += 1
            if done % 3 == 0 { await progress(Double(done) / Double(times.count)) }
            guard let image = try? result.image else { continue }
            let codes = ImageCodeReader.barcodes(in: image)
            guard let first = codes.first, !seen.contains(first.payload) else { continue }
            seen.insert(first.payload)
            // nieuwe kaart: nu ook de tekst lezen voor de winkelnaam
            guard var full = await ImageCodeReader.read(image) else { continue }
            if full.payload != first.payload {
                full.payload = first.payload
                full.format = first.format
            }
            await found(Found(result: full, frame: jpeg(image)))
        }
        await progress(1)
        try? FileManager.default.removeItem(at: url)
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        #if canImport(UIKit)
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
        #else
        return nil
        #endif
    }
}
