import SwiftUI

// MARK: - Tickets (gratis events) en klantenkaarten met barcode van een zaak (tk_business / event_cancel /
// member_card_archive), zoals beheer.pasr.nl. Alleen aantallen, geen persoonsgegevens van wie zich aanmeldde.

struct BusinessTK: Decodable {
    struct Event: Decodable, Identifiable {
        let id: String; let name: String; let starts_at: String; let ends_at: String; let address: String?
        let status: String; let capacity: Int; let registered: Int?; let checked_in: Int?; let waitlist: Int?; let cancelled: Int?
    }
    struct MemberCard: Decodable, Identifiable {
        let id: String; let name: String; let status: String; let barcode_type: String; let prefix: String?
        let members: Int?; let visits_30d: Int?; let goals: [String]?
    }
    let events: [Event]?
    let member_cards: [MemberCard]?
}

struct BusinessTicketsSection: View {
    let businessID: String
    let businessName: String
    @EnvironmentObject private var session: Session
    @State private var data: BusinessTK?
    @State private var error: String?
    @State private var cancelling: BusinessTK.Event?
    @State private var archiving: BusinessTK.MemberCard?

    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return Self.iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    private func when(_ s: String) -> String { date(s)?.formatted(date: .abbreviated, time: .shortened) ?? "—" }
    private func ended(_ e: BusinessTK.Event) -> Bool { (date(e.ends_at) ?? .distantFuture) < .now }
    private func state(_ s: String, past: Bool = false) -> String {
        if past && s == "published" { return String(localized: "afgelopen") }
        switch s {
        case "draft": return String(localized: "concept")
        case "published": return String(localized: "online")
        case "cancelled": return String(localized: "afgelast")
        case "archived": return String(localized: "gearchiveerd")
        default: return s
        }
    }
    private func barcode(_ t: String) -> String { t == "qr" ? "QR-code" : t == "ean13" ? "EAN-13" : "Code 128" }

    var body: some View {
        Section {
            if let error { Text(error).foregroundStyle(.red) }
            if let d = data {
                let events = d.events ?? [], cards = d.member_cards ?? []
                Text("\(events.count) events · \(cards.count) klantenkaarten · \(cards.reduce(0) { $0 + ($1.members ?? 0) }) leden")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(events) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Event: \(e.name) · \(when(e.starts_at))").font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text("\(state(e.status, past: ended(e))) · \(e.registered ?? 0)/\(e.capacity) aangemeld · \(e.checked_in ?? 0) binnen · \(e.waitlist ?? 0) wachtlijst · \(e.cancelled ?? 0) afgemeld")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if e.status != "cancelled" && !ended(e) {
                            Button("Afgelasten", role: .destructive) { cancelling = e }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                ForEach(cards) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Klantenkaart: \(c.name) · \(barcode(c.barcode_type))").font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text("\(state(c.status)) · \(c.members ?? 0) leden · \(c.visits_30d ?? 0) bezoeken (30 d)" + ((c.goals ?? []).isEmpty ? "" : " · " + (c.goals ?? []).joined(separator: " · ")))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if c.status != "archived" {
                            Button("Archiveren", role: .destructive) { archiving = c }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                if events.isEmpty && cards.isEmpty { Text("Nog geen events of klantenkaarten.").foregroundStyle(.secondary) }
            } else if error == nil {
                ProgressView()
            }
        } header: { Text("Tickets en klantenkaarten") }
        .task { await load() }
        .confirmationDialog(String(localized: "Event afgelasten?"), isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }), titleVisibility: .visible) {
            Button("Afgelasten", role: .destructive) {
                if let e = cancelling { Task { await cancel(e) } }
            }
        } message: {
            Text("\(cancelling?.name ?? "") van \(businessName) gaat niet door. Alle tickets vervallen; iedereen die zich aanmeldde krijgt een mail en een melding.")
        }
        .confirmationDialog(String(localized: "Klantenkaart archiveren?"), isPresented: Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } }), titleVisibility: .visible) {
            Button("Archiveren", role: .destructive) {
                if let c = archiving { Task { await archive(c) } }
            }
        } message: {
            Text("\(archiving?.name ?? "") kan daarna niet meer worden gescand en nieuwe klanten kunnen geen lid worden.")
        }
    }

    private func load() async {
        do { data = try await session.call("tk_business", ["id": businessID], as: BusinessTK.self); error = nil }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }

    private func cancel(_ e: BusinessTK.Event) async {
        do { try await session.call("event_cancel", ["id": e.id, "message": "Dit event is afgelast."]); await load() }
        catch { self.error = error.localizedDescription }
    }

    private func archive(_ c: BusinessTK.MemberCard) async {
        do { try await session.call("member_card_archive", ["id": c.id]); await load() }
        catch { self.error = error.localizedDescription }
    }
}
