import SwiftUI

/// Bovenaan Vandaag: wat nu aandacht vraagt (ondernemers die wachten, ongelezen mail per postvak).
struct AttentionCard: View {
    @EnvironmentObject private var session: Session
    @State private var pending = 0

    private var nothing: Bool { pending == 0 && session.mailUnread == 0 && session.mailUnreadOwners == 0 }

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("Aandacht nodig").font(.headline).padding(.bottom, 4)
                if nothing {
                    Text("Alles is bijgewerkt. Er wacht niets op jou.")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mint)
                }
                if pending > 0 {
                    row("rectangle.stack.badge.person.crop", Theme.amber,
                        pending == 1 ? String(localized: "1 ondernemer wacht op goedkeuring") : String(localized: "\(pending) ondernemers wachten op goedkeuring"),
                        String(localized: "Controleer de aanmelding en keur goed."), .businesses)
                }
                if session.mailUnread > 0 {
                    row("envelope.badge", Theme.iris2,
                        session.mailUnread == 1 ? String(localized: "1 ongelezen mail bij Support") : String(localized: "\(session.mailUnread) ongelezen mails bij Support"),
                        "support@pasr.nl", .supportMail)
                }
                if session.mailUnreadOwners > 0 {
                    row("envelope.badge", Theme.mint,
                        session.mailUnreadOwners == 1 ? String(localized: "1 ongelezen mail van ondernemers") : String(localized: "\(session.mailUnreadOwners) ongelezen mails van ondernemers"),
                        "zakelijk@pasr.nl", .ownersMail)
                }
            }
        }
        .task(id: session.refreshTick) {
            await session.refreshMailBadge()
            if let r = try? await session.call("businesses", as: BusinessesResponse.self) {
                pending = r.businesses.filter { $0.status == "pending" }.count
            }
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ detail: String, _ target: AppSection) -> some View {
        Button { session.section = target } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(verbatim: detail).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
