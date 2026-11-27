import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Huisstijl van Pasr (zelfde kleuren als de app Pasr en pasr.nl), met mint als accent voor "Zakelijk".
enum Theme {
    static let iris = Color(hex: "#6A5CFF")
    static let coral = Color(hex: "#FF6B57")
    static let mint = Color(hex: "#2ED3A6")
    static let amber = Color(hex: "#FFB547")
    static let sky = Color(hex: "#4FB3FF")
    /// Accentkleur van de app (knoppen, tint).
    static let accent = iris
    /// Achtergrond en kaarten: licht of donker volgens de weergave.
    static let bg = Color(light: 0xF4F3FF, dark: 0x0A0B10)
    static let card = Color(light: 0xFFFFFF, dark: 0x15171F)
    static let card2 = Color(light: 0xECEBFA, dark: 0x1C1F29)
    static let line = Color(light: 0xE1DFF2, dark: 0x262A37)
    static let muted = Color(light: 0x5F5D78, dark: 0x9A98B3)

    /// Grafiekkaart in de stijl van Homey Insights: kaart, pillen en raster (licht/donker).
    static let insightsCard = Color(light: 0xFFFFFF, dark: 0x1C1D26)
    static let insightsPill = Color(light: 0xF1F2F6, dark: 0x2A2B36)
    static let insightsGrid = Color(light: 0xE3E5EC, dark: 0x3A3C4A)

    static let gradient = LinearGradient(colors: [iris, coral], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Kleuren voor stempelkaarten (zelfde als het dashboard op pasr.nl).
    static let swatches = ["#6A5CFF", "#17162A", "#E30613", "#FF6B57", "#E2683C", "#F2B705",
                           "#2ED3A6", "#12A77E", "#0A84FF", "#7B4B2A", "#AF52DE", "#FF375F"]
}

/// Weergave: Automatisch (volgt iOS), Licht of Donker.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "ui.appearance"
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .system: "Automatisch"
        case .light: "Licht"
        case .dark: "Donker"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Color {
    /// Kleur met een eigen waarde voor licht en donker.
    init(light: UInt32, dark: UInt32) {
        func comps(_ v: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
        }
        #if os(iOS)
        self.init(uiColor: UIColor { trait in
            let (r, g, b) = comps(trait.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = comps(isDark ? dark : light)
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
        #endif
    }

    init(hex: String) {
        let (r, g, b) = Color.rgb(fromHex: hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    static func rgb(fromHex hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return (0.42, 0.36, 1) }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// Wit of bijna-zwart, wat het best leest op een kaart van deze kleur.
    static func onCard(_ hex: String) -> Color {
        let (r, g, b) = rgb(fromHex: hex)
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return l > 0.45 ? Color(hex: "#111216") : .white
    }

    /// "#RRGGBB" van deze kleur (sRGB).
    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(iOS)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        (NSColor(self).usingColorSpace(.sRGB) ?? .black).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        func c(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

/// Kaart met achtergrond en rand.
struct CardBox<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
    }
}

/// Grote knop in de stijl van Pasr.
struct BigButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(foreground)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Woordmerk "pasr ZAKELIJK" met het icoon.
struct ZakelijkLogo: View {
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: size * 0.4) {
            Image("AppIconDisplay")
                .resizable()
                .frame(width: size * 1.5, height: size * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.36, style: .continuous))
            Text(verbatim: "pasr")
                .font(.system(size: size, weight: .heavy))
                .tracking(-size * 0.03)
            Text("ZAKELIJK")
                .font(.system(size: max(9, size * 0.42), weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.mint)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(Theme.mint.opacity(0.6)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Pasr Zakelijk"))
    }
}
