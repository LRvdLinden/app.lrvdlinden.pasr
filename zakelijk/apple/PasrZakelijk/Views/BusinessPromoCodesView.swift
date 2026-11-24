import SwiftUI

/// Zelfgekozen, herbruikbare actiecodes. Dit is bewust gescheiden van persoonlijke PC-kortingsbonnen.
struct BusinessPromoCodesView: View {
    let business: Business
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var title = ""
    @State private var kind = "percent"
    @State private var value = "10"
    @State private var minimum = "0"
    @State private var maxUses = 100
    @State private var active = false
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var entries: [[String: Any]] = []
    @State private var verifyCode = ""
    @State private var verified = false
    @State private var editingID: String?
    @State private var removeID: String?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(editingID == nil ? "Nieuwe actiecode" : "Actiecode bewerken") {
                    if editingID != nil { Button("Annuleer bewerken") { editingID = nil; code = ""; title = "" } }
                    Text("De klant noemt de actiecode aan de kassa. Deze code is herbruikbaar tot de ingestelde limiet en is geen persoonlijke kortingsbon.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Code (bijv. HERFST20)", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Naam actie", text: $title)
                    Picker("Korting", selection: $kind) {
                        Text("Percentage (%)").tag("percent")
                        Text("Vast bedrag (€)").tag("amount")
                    }
                    TextField("Korting", text: $value).keyboardType(.decimalPad)
                    TextField("Minimale besteding (€)", text: $minimum).keyboardType(.decimalPad)
                    DatePicker("Startdatum", selection: $start, displayedComponents: .date)
                    DatePicker("Einddatum", selection: $end, in: start..., displayedComponents: .date)
                    Stepper("Maximaal \(maxUses) keer gebruiken", value: $maxUses, in: 1...100000)
                    Toggle("Actiecode activeren", isOn: $active)
                    Button(editingID == nil ? "Actiecode aanmaken" : "Wijzigingen opslaan") { Task { await save() } }
                        .disabled(busy || code.count < 4 || title.count < 3)
                }
                Section("Mijn actiecodes") {
                    if entries.isEmpty { Text("Nog geen actiecodes").foregroundStyle(.secondary) }
                    ForEach(entries.indices, id: \.self) { i in
                        let row = entries[i]
                        let id = row["id"] as? String ?? ""
                        let used = (row["used_count"] as? NSNumber)?.intValue ?? 0
                        VStack(alignment: .leading, spacing: 8) {
                            BusinessDiscountCard(business: business.name,
                                title: row["title"] as? String ?? "",
                                discountType: row["discount_type"] as? String ?? "amount",
                                discountValue: (row["discount_value"] as? NSNumber)?.doubleValue ?? 0,
                                color: business.cards.first?.color ?? "#6A5CFF",
                                logo: business.cards.first(where: { $0.logo != nil })?.logo,
                                kind: "Actiecode · \(row["code"] as? String ?? "")",
                                status: row["deleted"] as? Bool == true ? "Verwijderd" :
                                    (row["active"] as? Bool == true ? "Actief" : "Gepauzeerd"),
                                usage: "\(used) gebruikt")
                            HStack {
                                Button("Bewerken") { edit(row) }.disabled(row["deleted"] as? Bool == true)
                                Spacer()
                                Button("Verwijderen", role: .destructive) { removeID = id }
                                    .disabled(row["deleted"] as? Bool == true)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Section("Controleren en verzilveren") {
                    TextField("Persoonlijke PA-code uit Pasr", text: $verifyCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Controleer actiecode") { Task { await check() } }
                        .disabled(busy || verifyCode.isEmpty)
                    Button("Gebruik één keer registreren") { Task { await redeem() } }
                        .disabled(busy || !verified)
                    Text("Alleen een persoonlijke PA-code uit Pasr: Klantenkaarten kan worden verzilverd. De algemene actiecode is geen kassabewijs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Section { Text(message) } }
            }
            .navigationTitle("Actiecodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Klaar") { dismiss() }
            } }
            .confirmationDialog("Actiecode verwijderen?", isPresented: Binding(
                get: { removeID != nil }, set: { if !$0 { removeID = nil } }), titleVisibility: .visible) {
                Button("Verwijderen en onbruikbaar maken", role: .destructive) {
                    if let id = removeID { Task { await remove(id) } }
                    removeID = nil
                }
                Button("Annuleren", role: .cancel) { removeID = nil }
            } message: { Text("Gebruikshistorie blijft bestaan. Bestaande persoonlijke bewijzen worden geblokkeerd.") }
            .onChange(of: verifyCode) { _, _ in verified = false }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        do {
            let response = try await Account.shared.rpc("pasr_business_promo_list", ["p_business": business.id])
            entries = response as? [[String: Any]] ?? []
        } catch { message = error.localizedDescription }
    }

    @MainActor private func save() async {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.range(of: "^[A-Z0-9][A-Z0-9-]{3,23}$", options: .regularExpression) != nil,
              let amount = Double(value.replacingOccurrences(of: ",", with: ".")),
              let min = Double(minimum.replacingOccurrences(of: ",", with: ".")),
              amount > 0, min >= 0, end > start else {
            message = "Controleer code, bedragen en datums."; return
        }
        busy = true
        defer { busy = false }
        let iso = ISO8601DateFormatter()
        do {
            var payload: [String: Any] = [
                "business_id": business.id, "code": normalized, "title": title,
                "discount_type": kind, "discount_value": amount, "min_spend": min,
                "starts_at": iso.string(from: start), "ends_at": iso.string(from: end),
                "max_uses": maxUses, "active": active
            ]
            if let editingID { payload["id"] = editingID }
            _ = try await Account.shared.rpc("pasr_business_promo_save", ["p_promo": payload])
            message = "Actiecode opgeslagen."
            code = ""; title = ""; editingID = nil
            await load()
        } catch { message = error.localizedDescription }
    }

    @MainActor private func edit(_ row: [String: Any]) {
        editingID = row["id"] as? String
        code = row["code"] as? String ?? ""
        title = row["title"] as? String ?? ""
        kind = row["discount_type"] as? String ?? "percent"
        value = "\((row["discount_value"] as? NSNumber)?.doubleValue ?? 0)"
        minimum = "\((row["min_spend"] as? NSNumber)?.doubleValue ?? 0)"
        maxUses = (row["max_uses"] as? NSNumber)?.intValue ?? 100
        active = row["active"] as? Bool ?? false
        let parser = ISO8601DateFormatter()
        start = parser.date(from: row["starts_at"] as? String ?? "") ?? .now
        end = parser.date(from: row["ends_at"] as? String ?? "") ??
            Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        message = "Je kunt ook na publicatie wijzigingen opslaan."
    }

    @MainActor private func remove(_ id: String) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_discount_remove",
                ["p_business": business.id, "p_id": id, "p_kind": "code"])
            if editingID == id { editingID = nil; code = ""; title = "" }
            message = "Actiecode verwijderd en onbruikbaar; historie behouden."
            await load()
        } catch { message = error.localizedDescription }
    }

    @MainActor private func check() async {
        busy = true
        defer { busy = false }
        do {
            let response = try await Account.shared.rpc("pasr_business_promo_check",
                ["p_code": verifyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()])
            let result = JSONObject(response)
            verified = result?.bool("valid") ?? false
            message = verified ? "Geldige actie: \(result?.string("title") ?? "") · \(result?.string("discount_value") ?? "") korting" :
                "De actiecode is onbekend, verlopen, uitgeschakeld of opgebruikt."
        } catch { verified = false; message = error.localizedDescription }
    }

    @MainActor private func redeem() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_promo_redeem",
                ["p_code": verifyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()])
            verified = false
            message = "Actiecode geregistreerd als gebruikt."
            verifyCode = ""
            await load()
        } catch { verified = false; message = error.localizedDescription }
    }
}
