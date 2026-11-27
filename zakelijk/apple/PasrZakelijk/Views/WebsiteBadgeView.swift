import SwiftUI
import UIKit

/// "Knop voor je website": de knop "Voeg toe aan Pasr" voor een stempelkaart van de zaak. Kies zwart, wit of
/// nachtblauw en groot of compact; deel de HTML-code, de link (https://pasr.nl/add/k/<id>) of de QR-code.
/// De knop zelf is altijd Nederlands (badges uit tools/make_badges.py, ook op pasr.nl/badge/nl/).
struct WebsiteBadgeView: View {
    let card: BusinessCard
    @Environment(\.dismiss) private var dismiss
    @AppStorage("badge.theme") private var theme = "zwart"
    @AppStorage("badge.size") private var size = "groot"
    @State private var copied: String?

    private static let themes: [(String, LocalizedStringKey)] = [("zwart", "Zwart"), ("wit", "Wit"), ("nachtblauw", "Nachtblauw")]
    private static let sizes: [(String, LocalizedStringKey)] = [("groot", "Groot"), ("compact", "Compact")]

    private var file: String { theme + (size == "compact" ? "-compact" : "") }
    private var height: Int { size == "compact" ? 38 : 52 }
    private var addURL: URL { URL(string: "https://pasr.nl/add/k/\(card.id.lowercased())")! }
    private var snippet: String {
        "<a href=\"\(addURL.absoluteString)\">\n  <img src=\"https://pasr.nl/badge/nl/\(file).svg\"\n       alt=\"Voeg toe aan Pasr\" height=\"\(height)\">\n</a>"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Klanten zetten je stempelkaart met één tik in Pasr. Zonder Pasr opent pasr.nl met de downloadknoppen.")
                        .foregroundStyle(Theme.muted)
                    Picker("Kleur", selection: $theme) {
                        ForEach(Self.themes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Formaat", selection: $size) {
                        ForEach(Self.sizes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 0) {
                        preview.frame(maxWidth: .infinity, minHeight: 96).background(Color.white)
                        preview.frame(maxWidth: .infinity, minHeight: 96).background(Color(red: 0.09, green: 0.086, blue: 0.165))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Voorbeeld van de knop Voeg toe aan Pasr"))

                    Text("Zet deze code op je website").font(.headline)
                    Text(verbatim: snippet)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color(red: 0.91, green: 0.906, blue: 1))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.09, green: 0.086, blue: 0.165), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = snippet
                        copied = "code"
                    } label: {
                        Label(copied == "code" ? "Gekopieerd" : "Kopieer HTML-code", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(BigButtonStyle())
                    ShareLink(item: snippet, subject: Text(verbatim: card.name)) {
                        Label("Deel HTML-code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(BigButtonStyle(color: Theme.card2, foreground: .primary))

                    Text("Link").font(.headline)
                    Text(verbatim: addURL.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.muted)
                        .textSelection(.enabled)
                    ShareLink(item: addURL, subject: Text(verbatim: card.name)) {
                        Label("Link delen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BigButtonStyle(color: Theme.mint, foreground: .black))

                    Text("QR-code voor toonbank en kassabon").font(.headline)
                    if let qr = QRCode.image(addURL.absoluteString, scale: 12) {
                        HStack(alignment: .center, spacing: 16) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 132, height: 132)
                                .padding(8)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityLabel(Text("QR-code met de link"))
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Scannen met de camera opent dezelfde link: met Pasr meteen Toevoegen aan Pasr?, anders pasr.nl.")
                                    .font(.footnote).foregroundStyle(Theme.muted)
                                ShareLink(item: Image(uiImage: qr), preview: SharePreview(Text("QR-code"), image: Image(uiImage: qr))) {
                                    Label("Deel QR-code", systemImage: "qrcode")
                                }
                            }
                        }
                    }
                    if let png = UIImage(named: "PasrBadge-" + file) {
                        ShareLink(item: Image(uiImage: png), preview: SharePreview(Text("Voeg toe aan Pasr"), image: Image(uiImage: png))) {
                            Label("Knop als afbeelding (PNG)", systemImage: "photo")
                        }
                        .buttonStyle(BigButtonStyle(color: Theme.card2, foreground: .primary))
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(Text("Knop voor je website"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .onChange(of: theme) { _, _ in copied = nil }
            .onChange(of: size) { _, _ in copied = nil }
        }
    }

    private var preview: some View {
        Image("PasrBadge-" + file)
            .resizable()
            .scaledToFit()
            .frame(height: CGFloat(height))
            .padding(12)
    }
}
