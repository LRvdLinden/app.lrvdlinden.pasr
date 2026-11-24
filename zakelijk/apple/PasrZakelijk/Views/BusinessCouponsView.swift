import SwiftUI

/// Kortingsbonnen van deze zaak. Alleen de accountserver kan codes uitgeven en verzilveren.
struct BusinessCouponsView: View {
    let business: Business
    var initialCode: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var type = "amount"
    @State private var amount = "2.50"
    @State private var minimum = "10"
    @State private var count = 500
    @State private var start = Date()
    @State private var end = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var published = false
    @State private var onePerCustomer = true
    @State private var code = ""
    @State private var couponVerified = false
    @State private var rows: [CouponRow] = []
    @State private var editingID: String?
    @State private var removeID: String?
    @State private var busy = false
    @State private var status: String?

    struct CouponRow: Identifiable {
        let id: String
        let title: String
        let claimed: Int
        let redeemed: Int
        let published: Bool
        let raw: [String: Any]
        init?(_ json: [String: Any]) {
            guard let id = json["id"] as? String else { return nil }
            self.id = id
            raw = json
            title = json["title"] as? String ?? ""
            claimed = (json["claimed"] as? NSNumber)?.intValue ?? 0
            redeemed = (json["redeemed"] as? NSNumber)?.intValue ?? 0
            published = json["public"] as? Bool ?? false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(editingID == nil ? "Nieuwe kortingsbon" : "Kortingsbon bewerken") {
                    if editingID != nil {
                        Button("Annuleer bewerken") { editingID = nil; title = ""; description = "" }
                    }
                    TextField("Naam actie", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Omschrijving / voorwaarden", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Korting", selection: $type) {
                        Text("Vast bedrag (€)").tag("amount")
                        Text("Percentage (%)").tag("percent")
                    }
                    TextField(type == "amount" ? "Kortingsbedrag €" : "Percentage", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("Minimale besteding €", text: $minimum)
                        .keyboardType(.decimalPad)
                    DatePicker("Begindatum", selection: $start, displayedComponents: .date)
                    DatePicker("Einddatum", selection: $end, in: start..., displayedComponents: .date)
                    Stepper("Maximaal \(count) bonnen", value: $count, in: 1...100000)
                    Toggle("Een bon per klant", isOn: $onePerCustomer)
                    Toggle("Publiceren in Pasr", isOn: $published)
                    Button { Task { await create() } } label: {
                        HStack {
                            if busy { ProgressView() }
                            Label(editingID == nil ? "Kortingsbon aanmaken" : "Wijzigingen opslaan", systemImage: "ticket.fill")
                        }
                    }
                    .disabled(busy || title.trimmingCharacters(in: .whitespaces).count < 3)
                }
                Section("Bestaande kortingsbonnen") {
                    if rows.isEmpty { Text("Nog geen kortingsbonnen").foregroundStyle(.secondary) }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            BusinessDiscountCard(business: business.name, title: row.title,
                                discountType: row.raw["discount_type"] as? String ?? "amount",
                                discountValue: (row.raw["discount_value"] as? NSNumber)?.doubleValue ?? 0,
                                color: row.raw["color"] as? String ?? "#6A5CFF",
                                logo: row.raw["logo"] as? String,
                                kind: "Kortingscoupon",
                                status: row.raw["deleted"] as? Bool == true ? "Verwijderd" :
                                    (row.published ? "Actief" : "Gepauzeerd"),
                                usage: "\(row.redeemed) gebruikt")
                            HStack {
                                Button("Bewerken") { edit(row) }
                                    .disabled(row.raw["deleted"] as? Bool == true)
                                Spacer()
                                Button("Verwijderen", role: .destructive) { removeID = row.id }
                                    .disabled(row.raw["deleted"] as? Bool == true)
                            }
                            .buttonStyle(.borderless)
                            Text("\(row.claimed) bewaard · \(row.redeemed) gebruikt")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Aan de kassa verzilveren") {
                    Text("Controleer of de korting daadwerkelijk wordt gegeven. De code kan daarna nooit opnieuw gebruikt worden.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("PC-code van de klant", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Controleer bon") { Task { await checkCode() } }
                        .disabled(busy || !code.uppercased().hasPrefix("PC"))
                    Button("Bon definitief verzilveren") { Task { await redeem() } }
                        .disabled(busy || !couponVerified)
                }
                if let status {
                    Section { Text(status).font(.subheadline) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Kortingsbonnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Klaar") { dismiss() }
            } }
            .confirmationDialog("Kortingscoupon verwijderen?", isPresented: Binding(
                get: { removeID != nil }, set: { if !$0 { removeID = nil } }), titleVisibility: .visible) {
                Button("Verwijderen en onbruikbaar maken", role: .destructive) {
                    if let id = removeID { Task { await remove(id) } }
                    removeID = nil
                }
                Button("Annuleren", role: .cancel) { removeID = nil }
            } message: {
                Text("Gebruikte bonnen blijven in de historie en nieuwe verzilveringen worden geblokkeerd.")
            }
            .onChange(of: code) { _, _ in couponVerified = false }
            .task { code = initialCode; await load(); if !code.isEmpty { await checkCode() } }
        }
    }

    @MainActor private func load() async {
        do {
            let response = try await Account.shared.rpc("pasr_business_coupon_list", ["p_business": business.id])
            rows = (response as? [[String: Any]] ?? []).compactMap(CouponRow.init)
        } catch { status = error.localizedDescription }
    }

    @MainActor private func create() async {
        guard let discount = Double(amount.replacingOccurrences(of: ",", with: ".")), discount > 0,
              let minSpend = Double(minimum.replacingOccurrences(of: ",", with: ".")), minSpend >= 0,
              end > start else { status = "Controleer bedrag, minimum en datums."; return }
        busy = true
        defer { busy = false }
        let iso = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "business_id": business.id,
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": description,
            "discount_type": type,
            "discount_value": discount,
            "min_spend": minSpend,
            "starts_at": iso.string(from: start),
            "ends_at": iso.string(from: end),
            "max_claims": count,
            "one_per_customer": onePerCustomer,
            "public": published
        ]
        if let editingID { payload["id"] = editingID }
        do {
            _ = try await Account.shared.rpc("pasr_business_coupon_save", ["p_coupon": payload])
            status = "Kortingsbon opgeslagen."
            title = ""; description = ""; editingID = nil
            await load()
        } catch { status = error.localizedDescription }
    }

    @MainActor private func edit(_ row: CouponRow) {
        let data = row.raw
        editingID = row.id
        title = row.title
        description = data["description"] as? String ?? ""
        type = data["discount_type"] as? String ?? "amount"
        amount = "\((data["discount_value"] as? NSNumber)?.doubleValue ?? 0)"
        minimum = "\((data["min_spend"] as? NSNumber)?.doubleValue ?? 0)"
        count = (data["max_claims"] as? NSNumber)?.intValue ?? 500
        onePerCustomer = data["one_per_customer"] as? Bool ?? true
        published = row.published
        let parser = ISO8601DateFormatter()
        start = parser.date(from: data["starts_at"] as? String ?? "") ?? .now
        end = parser.date(from: data["ends_at"] as? String ?? "") ??
            Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        status = "Deze coupon kan ook na publicatie aangepast worden."
    }

    @MainActor private func remove(_ id: String) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_discount_remove",
                ["p_business": business.id, "p_id": id, "p_kind": "coupon"])
            if editingID == id { editingID = nil; title = ""; description = "" }
            status = "Kortingscoupon verwijderd en onbruikbaar; historie behouden."
            await load()
        } catch { status = error.localizedDescription }
    }

    @MainActor private func checkCode() async {
        do {
            let response = try await Account.shared.rpc("pasr_business_coupon_check",
                ["p_code": code.uppercased().trimmingCharacters(in: .whitespaces)])
            let result = JSONObject(response)
            couponVerified = result?.bool("valid") ?? false
            status = couponVerified ?
                "Geldige bon: \(result?.string("title") ?? "") · korting \(result?.string("discount_value") ?? "")" :
                "Deze kortingsbon is al gebruikt, verlopen of ongeldig."
        } catch {
            couponVerified = false
            status = error.localizedDescription
        }
    }

    @MainActor private func redeem() async {
        busy = true
        defer { busy = false }
        do {
            let response = try await Account.shared.rpc("pasr_business_coupon_redeem", ["p_code": code.uppercased().trimmingCharacters(in: .whitespaces)])
            let result = JSONObject(response)
            status = "Bon verzilverd: \(result?.string("title") ?? "kortingsbon")"
            code = ""
            couponVerified = false
            await load()
        } catch { status = error.localizedDescription }
    }
}
