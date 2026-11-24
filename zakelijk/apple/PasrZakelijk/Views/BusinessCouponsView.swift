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
    @State private var busy = false
    @State private var status: String?

    struct CouponRow: Identifiable {
        let id: String
        let title: String
        let claimed: Int
        let redeemed: Int
        let published: Bool
        init?(_ json: [String: Any]) {
            guard let id = json["id"] as? String else { return nil }
            self.id = id
            title = json["title"] as? String ?? ""
            claimed = (json["claimed"] as? NSNumber)?.intValue ?? 0
            redeemed = (json["redeemed"] as? NSNumber)?.intValue ?? 0
            published = json["public"] as? Bool ?? false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nieuwe kortingsbon") {
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
                            Label("Kortingsbon aanmaken", systemImage: "ticket.fill")
                        }
                    }
                    .disabled(busy || title.trimmingCharacters(in: .whitespaces).count < 3)
                }
                Section("Bestaande kortingsbonnen") {
                    if rows.isEmpty { Text("Nog geen kortingsbonnen").foregroundStyle(.secondary) }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(.headline)
                            Text("\(row.claimed) bewaard · \(row.redeemed) gebruikt · \(row.published ? "Gepubliceerd" : "Concept")")
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
        let payload: [String: Any] = [
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
        do {
            _ = try await Account.shared.rpc("pasr_business_coupon_save", ["p_coupon": payload])
            status = "Kortingsbon opgeslagen."
            title = ""; description = ""
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
