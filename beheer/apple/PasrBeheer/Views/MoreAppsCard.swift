import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// Kaart "Meer apps van de ontwikkelaar" (overgenomen uit Homey-Store-ios, HomeyAppStore/Views/Components/MoreAppsCard.swift),
// in de huisstijl van lrvdlinden.app. Zelfde bestand in Pasr en PasrBeheer.

/// LRvdLinden house style (from lrvdlinden.app): accent blue, ink, surface, line
/// and muted text, each with its dark-mode value.
enum LRBrand {
    static let url = URL(string: "https://lrvdlinden.app")!
    static let accent = Color(light: 0x2747E8, dark: 0x8A9DFF)
    static let accentSoft = Color(light: 0xE6EBFF, dark: 0x1D2547)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0D1018)
    static let ink = Color(light: 0x121726, dark: 0xE9ECF4)
    static let muted = Color(light: 0x5D6578, dark: 0x98A0B3)
    static let surface = Color(light: 0xFFFFFF, dark: 0x161B27)
    static let line = Color(light: 0xDDE2EC, dark: 0x262D3D)
    /// The logo tile is always the dark ink, with the blue dot.
    static let logoTile = Color(red: 0x12 / 255, green: 0x17 / 255, blue: 0x26 / 255)
    static let logoDot = Color(red: 0x4C / 255, green: 0x6B / 255, blue: 0xFF / 255)
}

/// The "LR" mark from lrvdlinden.app, drawn natively (512 × 512 design grid).
struct LRLogo: View {
    var size: CGFloat = 60

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 512
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: 116 * s, style: .continuous),
                     with: .color(LRBrand.logoTile))

            var letters = Path()
            // L
            letters.move(to: p(132, 146)); letters.addLine(to: p(132, 370)); letters.addLine(to: p(232, 370))
            // R: stem + bowl
            letters.move(to: p(292, 370)); letters.addLine(to: p(292, 146)); letters.addLine(to: p(340, 146))
            letters.addArc(center: p(340, 208), radius: 62 * s, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            letters.addLine(to: p(292, 270))
            // R: leg
            letters.move(to: p(338, 270)); letters.addLine(to: p(390, 370))
            ctx.stroke(letters, with: .color(.white),
                       style: StrokeStyle(lineWidth: 46 * s, lineCap: .round, lineJoin: .round))

            let dot = Path(ellipseIn: CGRect(x: (404 - 34) * s, y: (126 - 34) * s, width: 68 * s, height: 68 * s))
            ctx.fill(dot, with: .color(LRBrand.logoDot))
            ctx.stroke(dot, with: .color(LRBrand.logoTile), lineWidth: 14 * s)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "More apps from the developer" card for the bottom of a settings screen.
/// Opens lrvdlinden.app. Texts follow the app's language (10 languages).
struct MoreAppsCard: View {
    @ScaledMetric(relativeTo: .body) private var logoSize: CGFloat = 60

    private var text: MoreAppsText { MoreAppsText.current }

    var body: some View {
        Link(destination: LRBrand.url) {
            HStack(spacing: 14) {
                LRLogo(size: logoSize)
                    .overlay(RoundedRectangle(cornerRadius: logoSize * 116 / 512, style: .continuous)
                        .strokeBorder(LRBrand.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(text.title)
                        .font(.headline)
                        .foregroundStyle(LRBrand.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(LRBrand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(spacing: 4) {
                    Text(text.action)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(LRBrand.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(LRBrand.accent, in: Capsule())
                    Text("lrvdlinden.app")
                        .font(.caption2)
                        .foregroundStyle(LRBrand.muted)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .background(LRBrand.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(LRBrand.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text.title). \(text.subtitle)")
        .accessibilityHint("lrvdlinden.app")
        .accessibilityAddTraits(.isLink)
    }
}

/// Card texts per language; picks the app's language, English when unknown.
struct MoreAppsText {
    let section: String
    let title: String
    let subtitle: String
    let action: String

    /// Taal waarin de app draait (Pasr: Nederlands), anders de eerste voorkeurstaal, anders Engels.
    static var current: MoreAppsText {
        let codes = (Bundle.main.preferredLocalizations + Locale.preferredLanguages).map { String($0.prefix(2)).lowercased() }
        for c in codes { if let t = all[c == "nb" || c == "nn" ? "no" : c] { return t } }
        return all["en"]!
    }

    static let all: [String: MoreAppsText] = [
        "nl": .init(section: "Ontdekken", title: "Meer apps van de ontwikkelaar",
                    subtitle: "Apps voor iPhone, iPad, Apple TV en Homey", action: "Bekijk"),
        "en": .init(section: "Discover", title: "More apps from the developer",
                    subtitle: "Apps for iPhone, iPad, Apple TV and Homey", action: "View"),
        "de": .init(section: "Entdecken", title: "Weitere Apps des Entwicklers",
                    subtitle: "Apps für iPhone, iPad, Apple TV und Homey", action: "Ansehen"),
        "fr": .init(section: "Découvrir", title: "Plus d’apps du développeur",
                    subtitle: "Apps pour iPhone, iPad, Apple TV et Homey", action: "Voir"),
        "es": .init(section: "Descubrir", title: "Más apps del desarrollador",
                    subtitle: "Apps para iPhone, iPad, Apple TV y Homey", action: "Ver"),
        "it": .init(section: "Scopri", title: "Altre app dello sviluppatore",
                    subtitle: "App per iPhone, iPad, Apple TV e Homey", action: "Vedi"),
        "sv": .init(section: "Upptäck", title: "Fler appar från utvecklaren",
                    subtitle: "Appar för iPhone, iPad, Apple TV och Homey", action: "Visa"),
        "no": .init(section: "Oppdag", title: "Flere apper fra utvikleren",
                    subtitle: "Apper for iPhone, iPad, Apple TV og Homey", action: "Vis"),
        "da": .init(section: "Opdag", title: "Flere apps fra udvikleren",
                    subtitle: "Apps til iPhone, iPad, Apple TV og Homey", action: "Vis"),
        "pl": .init(section: "Odkrywaj", title: "Więcej aplikacji od dewelopera",
                    subtitle: "Aplikacje na iPhone’a, iPada, Apple TV i Homey", action: "Zobacz"),
    ]
}

#Preview {
    VStack(spacing: 20) {
        MoreAppsCard()
        MoreAppsCard().environment(\.colorScheme, .dark)
    }
    .padding()
}

extension Color {
    /// Kleur met een eigen waarde voor licht en donker.
    init(light: UInt32, dark: UInt32) {
        func comps(_ v: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
        }
        #if canImport(UIKit)
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
}
