import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum Brand {
    static let ink = Color(hex: "#0A0B10")
    static let inkRaised = Color(hex: "#15171F")
    static let iris = Color(hex: "#6A5CFF")
    static let coral = Color(hex: "#FF6B57")
    static let mint = Color(hex: "#2ED3A6")

    static let gradient = LinearGradient(colors: [iris, coral], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Card colours offered in the editor.
    static let palette: [String] = [
        "#6A5CFF", "#FF6B57", "#2ED3A6", "#0A84FF", "#FF9F0A", "#FF375F",
        "#30B0C7", "#5E5CE6", "#34C759", "#AF52DE", "#1C1C1E", "#8E8E93",
    ]

    /// Standard card ratio (ISO/IEC 7810 ID-1).
    static let cardAspect: CGFloat = 1.586
}

extension Color {
    init(hex: String) {
        let (r, g, b) = Color.rgb(fromHex: hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    static func rgb(fromHex hex: String) -> (Double, Double, Double) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return (0.17, 0.18, 0.23) }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// White or near-black, whichever reads best on a card of this colour.
    static func onCard(_ hex: String) -> Color {
        let (r, g, b) = rgb(fromHex: hex)
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return luminance > 0.45 ? Color(hex: "#111216") : .white
    }

    /// The same hue made lighter (positive amount) or darker (negative amount).
    static func shade(_ hex: String, by amount: Double) -> Color {
        let (r, g, b) = rgb(fromHex: hex)
        func adjust(_ c: Double) -> Double { amount >= 0 ? c + (1 - c) * amount : c * (1 + amount) }
        return Color(.sRGB, red: adjust(r), green: adjust(g), blue: adjust(b), opacity: 1)
    }
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
extension Image {
    init?(data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
    }
}
extension Color {
    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(max(0, min(1, r)) * 255)),
                      Int(round(max(0, min(1, g)) * 255)), Int(round(max(0, min(1, b)) * 255)))
    }
}
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
extension Image {
    init?(data: Data) {
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
    }
}
extension Color {
    func hexString() -> String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#2B2F3A" }
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
#endif
