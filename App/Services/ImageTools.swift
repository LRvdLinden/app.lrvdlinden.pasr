import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Image helpers built on ImageIO, so they behave the same on iPhone, iPad and Apple Watch.
enum ImageTools {
    /// Decodes image data upright (camera photos carry their rotation in EXIF), at most `maxSide` pixels.
    /// For multi-image files such as .ico it picks the largest image.
    static func cgImage(from data: Data, maxSide: Int = 2400) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var best = 0, bestSize = 0
        for index in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
            if w * h > bestSize { bestSize = w * h; best = index }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, best, options as CFDictionary)
    }

    /// PNG of the image, scaled down so its longest side is at most `maxSide`.
    static func png(_ image: CGImage, maxSide: Int = 256) -> Data? {
        let scale = min(1, CGFloat(maxSide) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Cuts a part out of the image. `rect` is normalised: 0...1 on both axes, origin top-left.
    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let pixels = CGRect(x: rect.minX * CGFloat(image.width), y: rect.minY * CGFloat(image.height),
                            width: rect.width * CGFloat(image.width), height: rect.height * CGFloat(image.height))
            .integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !pixels.isEmpty else { return nil }
        return image.cropping(to: pixels)
    }
}
