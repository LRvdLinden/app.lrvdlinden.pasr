import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Gedecodeerde logo's en kaartontwerpen, zodat een lijst van honderden winkels niet bij elke weergave base64 hoeft te lezen.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, CGImage>()

    private init() { cache.countLimit = 1500 }

    subscript(key: String) -> CGImage? {
        get { cache.object(forKey: key as NSString) }
        set {
            if let newValue { cache.setObject(newValue, forKey: key as NSString) } else { cache.removeObject(forKey: key as NSString) }
        }
    }

    /// base64 (PNG/JPEG/WebP) naar een verkleinde afbeelding van hoogstens `maxPixel` pixels.
    static func decode(_ base64: String, maxPixel: Int) -> CGImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                     kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

private struct ImageBox: @unchecked Sendable { let image: CGImage? }

/// Afbeelding uit base64, pas gedecodeerd als de rij in beeld komt, buiten de hoofdthread en daarna uit de cache.
struct CachedImage<Content: View>: View {
    let key: String
    let base64: String?
    let maxPixel: Int
    let content: (CGImage?) -> Content
    @State private var image: CGImage?

    init(key: String, base64: String?, maxPixel: Int = 160, @ViewBuilder content: @escaping (CGImage?) -> Content) {
        self.key = key
        self.base64 = base64
        self.maxPixel = maxPixel
        self.content = content
        _image = State(initialValue: base64 == nil ? nil : ImageCache.shared[key])
    }

    var body: some View {
        content(image)
            .task(id: key) {
                guard let base64, !base64.isEmpty else { image = nil; return }
                if let hit = ImageCache.shared[key] { image = hit; return }
                let size = maxPixel
                let box = await Task.detached(priority: .utility) { ImageBox(image: ImageCache.decode(base64, maxPixel: size)) }.value
                guard !Task.isCancelled else { return }
                if let img = box.image { ImageCache.shared[key] = img }
                image = box.image
            }
    }
}

/// Kaartontwerp maken zoals beheer/web (makeCover) en tools/make_covers.py: midden bijsnijden tot 1,586:1,
/// verkleinen tot 640 x 404 en als JPEG (kwaliteit 0,8, zo nodig lager) onder de grens van de backend (COVER_MAX).
enum CoverMaker {
    static let ratio = 1.586
    static let width = 640
    static let height = 404 // round(640 / 1.586)
    /// Iets onder COVER_MAX (210.000 tekens base64), net als het web-beheer.
    static let limit = 200_000

    enum Failure: LocalizedError {
        case unreadable, tooLarge
        var errorDescription: String? {
            switch self {
            case .unreadable: "Dit bestand is geen bruikbare afbeelding."
            case .tooLarge: "Het kaartontwerp is te groot."
            }
        }
    }

    static func make(_ data: Data) throws -> String {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadable }
        // eerst verkleind inlezen (met de juiste draaiing), zo blijven grote foto's licht
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw Failure.unreadable }
        var sw = Double(image.width), sh = Double(image.height), sx = 0.0, sy = 0.0
        guard sw > 0, sh > 0 else { throw Failure.unreadable }
        if sw / sh > ratio {
            let nw = (sh * ratio).rounded(); sx = ((sw - nw) / 2).rounded(.down); sw = nw
        } else {
            let nh = (sw / ratio).rounded(); sy = ((sh - nh) / 2).rounded(.down); sh = nh
        }
        guard let cropped = image.cropping(to: CGRect(x: sx, y: sy, width: sw, height: sh)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Failure.unreadable }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)) // doorzichtige PNG's op wit, zoals het web
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: rect)
        guard let out = ctx.makeImage() else { throw Failure.unreadable }
        var quality = 0.8
        while quality > 0.35 {
            let buffer = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.unreadable }
            CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw Failure.unreadable }
            let b64 = (buffer as Data).base64EncodedString()
            if b64.count <= limit { return b64 }
            quality -= 0.1
        }
        throw Failure.tooLarge
    }
}

/// Datum van "Gecontroleerd op" in de gids: YYYY-MM-DD (lokale kalenderdag).
enum GuideDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func string(_ d: Date) -> String { formatter.string(from: d) }
    static func date(_ s: String) -> Date? { formatter.date(from: s) }
}

/// Zoeken zonder hoofdletters en accenten ("Hema" vindt "HEMA", "cafe" vindt "Café").
enum SearchText {
    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    static func matches(_ query: String, _ fields: [String?]) -> Bool {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return true }
        return fields.contains { ($0.map(fold) ?? "").contains(q) }
    }
}
