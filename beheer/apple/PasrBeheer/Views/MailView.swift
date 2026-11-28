import SwiftUI

/// Een postvak (Support of Ondernemers): Inbox, Verzonden, Nieuwe mail en Nieuwsbrief. Concepten blijven bewaard (alleen in het geheugen) als je wisselt van onderdeel.
struct MailView: View {
    enum Part: String, CaseIterable, Identifiable {
        case inbox, sent, compose, newsletter
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .inbox: "Inbox"
            case .sent: "Verzonden"
            case .compose: "Nieuwe mail"
            case .newsletter: "Nieuwsbrief"
            }
        }
    }

    /// Het postvak: bepaalt het merk, het afzenderadres, de tickets en de doelgroep van de nieuwsbrief.
    let box: MailBrand

    @EnvironmentObject private var session: Session
    @State private var part: Part = .inbox
    @State private var status: MailStatus?
    private let drafts = MailDrafts.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("Onderdeel", selection: $part) {
                ForEach(Part.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            Group {
                switch part {
                case .inbox: MailInboxView(box: "inbox", mailbox: box, status: status, reloadStatus: reloadStatus)
                case .sent: MailInboxView(box: "sent", mailbox: box, status: status, reloadStatus: reloadStatus)
                case .compose: MailComposeView(status: status, draft: drafts.compose(for: box))
                case .newsletter: MailNewsletterView(status: status, draft: drafts.newsletter(for: box))
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle(Text(verbatim: box.boxTitle))
        .task(id: "\(box.rawValue)|\(session.refreshTick)") { await reloadStatus() }
        .id(box)
    }

    private func reloadStatus() async {
        do {
            let s = try await session.call("mail_status", as: MailStatus.self)
            status = s
            await session.refreshMailBadge()
        } catch {
            // zonder status werkt de rest nog (de server kan nog niet zijn bijgewerkt)
        }
    }
}
