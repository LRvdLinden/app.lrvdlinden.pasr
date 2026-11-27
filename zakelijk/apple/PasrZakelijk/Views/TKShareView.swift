import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Delen van een event of klantenkaart: QR-code, link en de knop "Voeg toe aan Pasr" voor de website.
struct TKShareView: View {
    let title: String
    let url: URL
    let intro: LocalizedStringKey
    let badgeIntro: LocalizedStringKey
    @Environment(\.dismiss) private var dismiss
    @State private var badge = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text(intro)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let qr = QRCode.image(url.absoluteString) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .accessibilityLabel(Text("QR-code met de link"))
                        ShareLink(item: Image(uiImage: qr), preview: SharePreview(Text("QR-code"), image: Image(uiImage: qr))) {
                            Label("Deel QR-code", systemImage: "qrcode")
                        }
                    }
                    Text(verbatim: url.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                    ShareLink(item: url, subject: Text(verbatim: title)) {
                        Label("Link delen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BigButtonStyle())
                    Button {
                        UIPasteboard.general.url = url
                    } label: {
                        Label("Kopieer link", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(BigButtonStyle(color: Theme.card2, foreground: .primary))
                    Button { badge = true } label: {
                        Label("Knop voor je website", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(BigButtonStyle(color: Theme.mint, foreground: .black))
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(Text(verbatim: title))
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .sheet(isPresented: $badge) {
                WebsiteBadgeView(url: url, name: title, intro: badgeIntro)
            }
        }
    }
}

/// Kleine statuspil: Online, Concept, Geannuleerd, Gearchiveerd.
struct TKStatusPill: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var label: LocalizedStringKey {
        switch status {
        case "published": "Online"
        case "cancelled": "Geannuleerd"
        case "archived": "Gearchiveerd"
        default: "Concept"
        }
    }

    private var color: Color {
        switch status {
        case "published": Theme.mint
        case "cancelled": Theme.coral
        default: Theme.muted
        }
    }
}

/// Kleurkiezer met "kleur van je zaak" (nil) en de vaste kleuren.
struct TKColorRow: View {
    @Binding var color: String?
    var allowDefault = true

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
            if allowDefault {
                Button { color = nil } label: {
                    Circle().fill(Theme.gradient).frame(height: 34)
                        .overlay(Image(systemName: "building.2").font(.caption.weight(.bold)).foregroundStyle(.white))
                        .overlay(Circle().strokeBorder(.primary, lineWidth: color == nil ? 3 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Kleur van je zaak"))
            }
            ForEach(Theme.swatches, id: \.self) { hex in
                Button { color = hex } label: {
                    Circle().fill(Color(hex: hex)).frame(height: 34)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: color?.uppercased() == hex ? 3 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: hex))
            }
        }
        .padding(.vertical, 4)
    }
}
