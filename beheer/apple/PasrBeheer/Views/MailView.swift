import SwiftUI

/// Tabblad Mail: Inbox, Nieuwe mail en Nieuwsbrief. Concepten blijven bewaard (alleen in het geheugen) als je wisselt van onderdeel.
struct MailView: View {
    enum Part: String, CaseIterable, Identifiable {
        case inbox, compose, newsletter
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .inbox: "Inbox"
            case .compose: "Nieuwe mail"
            case .newsletter: "Nieuwsbrief"
            }
        }
    }

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
                case .inbox: MailInboxView(status: status, reloadStatus: reloadStatus)
                case .compose: MailComposeView(status: status, draft: drafts.compose)
                case .newsletter: MailNewsletterView(status: status, draft: drafts.newsletter)
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle("Mail")
        .task(id: session.refreshTick) { await reloadStatus() }
    }

    private func reloadStatus() async {
        do {
            let s = try await session.call("mail_status", as: MailStatus.self)
            status = s
            session.mailUnread = s.counts?.unread ?? 0
        } catch {
            // zonder status werkt de rest nog (de server kan nog niet zijn bijgewerkt)
        }
    }
}
