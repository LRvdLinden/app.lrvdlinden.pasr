import SwiftUI

/// "Voeg toe aan Pasr": de link https://pasr.nl/add/<soort>/<id> van een stempelkaart (k) of een winkel uit de
/// catalogus (s, cadeaukaart g, ticket t) en een voorbeeld van de knop (badges op pasr.nl/badge/nl/). Zelfde als op
/// beheer.pasr.nl en in LRbeheer.
struct AddToPasrLinkSection: View {
    let kind: String
    let id: String
    var live = true

    private var url: String { "https://pasr.nl/add/\(kind)/\(["k", "c", "a"].contains(kind) ? id.lowercased() : id)" }

    var body: some View {
        Section {
            Text(url).font(.caption.monospaced()).textSelection(.enabled)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(["zwart", "wit", "nachtblauw"], id: \.self) { theme in
                        AsyncImage(url: URL(string: "https://pasr.nl/badge/nl/\(theme)@2x.png")) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 9).fill(.quaternary)
                        }
                        .frame(width: 115, height: 40)
                        .accessibilityLabel(Text("Voeg toe aan Pasr (\(theme))"))
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Button("Kopieer link", systemImage: "doc.on.doc") { Clipboard.copy(url) }
                if let link = URL(string: url) { Link(destination: link) { Label("Open", systemImage: "safari") } }
            }
            .buttonStyle(.bordered).controlSize(.small)
        } header: {
            Text("Voeg toe aan Pasr")
        } footer: {
            Text(live ? "De knop voor websites, mails en QR-codes. Met Pasr opent de link Toevoegen aan Pasr?, anders pasr.nl met de downloadknoppen."
                 : "Werkt zodra het item online staat.")
        }
    }
}
