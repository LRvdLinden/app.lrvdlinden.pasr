import SwiftUI

/// Wat is nieuw in deze versie.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    item("bell.badge", "Meldingen", AppPlatform.isMac
                         ? "Belangrijke berichten van Pasr Zakelijk als melding. Een klik op een melding met een link opent die link in de app."
                         : "Belangrijke berichten van Pasr Zakelijk als pushmelding. Een tik op een melding met een link opent die link in de app.")
                } header: {
                    Text(verbatim: "1.0.0 (4)")
                }
                Section {
                    item("qrcode.viewfinder", "Scannen aan de kassa", AppPlatform.isMac
                         ? "Scan de QR-code van je klant, kies het aantal stempels en klik op Stempels toevoegen."
                         : "Scan de QR-code van je klant, kies het aantal stempels en tik op Stempels toevoegen.")
                    item("gift", "Beloning inwisselen", AppPlatform.isMac
                         ? "Is de kaart vol, dan wissel je de beloning in met één klik."
                         : "Is de kaart vol, dan wissel je de beloning in met één tik.")
                    item("arrow.uturn.backward", "Ongedaan maken", "Vergist? Maak de laatste stempel of inwisseling binnen 2 minuten ongedaan.")
                    item("timer", "Afkoeltijd", "Een klant krijgt niet twee keer kort na elkaar een stempel. Je kiest zelf hoe lang.")
                    item("person.2", "Medewerkers", "Nodig je team uit met een link. Medewerkers zien alleen de scanner.")
                    item("chart.xyaxis.line", "Overzicht en logboek", "Stempels, beloningen en nieuwe leden per dag, en wie wat deed.")
                    item("printer", "Flyer", "Deel de QR-code of maak een A4-flyer voor op de toonbank.")
                    if AppPlatform.isMac {
                        item("touchid", "Vergrendelen met Touch ID", "Zet in Instellingen de vergrendeling aan; bij openen vraagt de app om Touch ID of het wachtwoord van je Mac.")
                    } else {
                        item("faceid", "Vergrendelen met Face ID", "Zet in Instellingen de vergrendeling aan; bij openen vraagt de app om Face ID, Touch ID of je toegangscode.")
                    }
                    item("mappin.and.ellipse", "Vindbaar in Pasr", "Klanten vinden je stempelkaart in de lijst in Pasr, ook in de buurt.")
                } header: {
                    Text(verbatim: "1.0.0")
                }
            }
            .navigationTitle("Wat is nieuw")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
        }
    }

    private func item(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.mint).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
