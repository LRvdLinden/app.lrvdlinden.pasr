import SwiftUI
import CoreImage.CIFilterBuiltins

/// Kortingsbonnen van goedgekeurde Pasr-ondernemers.
/// Persoonlijke codes komen uitsluitend van de server; de app kan niet zelf inwisselen.
struct PasrCouponsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Coupon] = []
    @State private var saved: [Claim] = []
    @State private var selected: Claim?
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?

    struct Coupon: Identifiable {
        let id: String
        let business: String
        let title: String
        let text: String
        let kind: String
        let amount: Double
        let minimum: Double
        let end: Date?
        let logo: String?
        let color: String
        let isPromo: Bool

        init?(_ json: [String: Any]) {
            guard let id = json["id"] as? String,
                  let title = json["title"] as? String else { return nil }
            self.id = id
            self.title = title
            logo = json["logo"] as? String
            color = json["color"] as? String ?? "#6A5CFF"
            isPromo = json["kind"] as? String == "code"
            business = json["business"] as? String ?? "Ondernemer"
            text = json["description"] as? String ?? ""
            kind = json["discount_type"] as? String ?? "amount"
            amount = (json["discount_value"] as? NSNumber)?.doubleValue ?? Double(json["discount_value"] as? String ?? "") ?? 0
            minimum = (json["min_spend"] as? NSNumber)?.doubleValue ?? Double(json["min_spend"] as? String ?? "") ?? 0
            end = ISO8601DateFormatter().date(from: json["ends_at"] as? String ?? "")
        }
        var discount: String {
            kind == "percent" ? "\(amount.formatted())% korting" :
            "\(amount.formatted(.currency(code: "EUR"))) korting"
        }
    }

    struct Claim: Identifiable {
        let id: String
        let code: String?
        let title: String
        let business: String
        let redeemed: Bool
        let disabled: Bool
        let end: Date?
        let logo: String?
        let color: String
        let amount: Double
        let discountType: String
        let isPromo: Bool

        init?(_ json: [String: Any]) {
            guard let id = json["id"] as? String else { return nil }
            self.id = id
            self.code = json["code"] as? String
            disabled = json["disabled"] as? Bool ?? false
            end = ISO8601DateFormatter().date(from: json["ends_at"] as? String ?? "")
            logo = json["logo"] as? String
            color = json["color"] as? String ?? "#6A5CFF"
            amount = (json["discount_value"] as? NSNumber)?.doubleValue ?? 0
            discountType = json["discount_type"] as? String ?? "amount"
            isPromo = json["kind"] as? String == "code"
            title = json["title"] as? String ?? "Kortingsbon"
            business = json["business"] as? String ?? ""
            redeemed = json["redeemed"] as? Bool ?? false
        }
    }

    private var filtered: [Coupon] {
        query.isEmpty ? items : items.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.business.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !saved.isEmpty {
                        Text("Mijn kortingsbonnen").font(.title3.bold())
                        ForEach(saved) { claim in
                            Button { selected = claim } label: {
                                PasrDiscountCard(business: claim.business, title: claim.title,
                                    discount: claim.discountType == "percent" ? "\(claim.amount.formatted())% korting" : "\(claim.amount.formatted(.currency(code: "EUR"))) korting",
                                    kind: claim.isPromo ? "Actiecode" : "Kortingscoupon",
                                    logo: claim.logo, color: claim.color,
                                    state: claim.redeemed ? .used : claim.disabled ? .paused : ((claim.end ?? .distantFuture) < .now ? .expired : .saved),
                                    expires: claim.end)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Aanbiedingen").font(.title3.bold())
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let error {
                        ContentUnavailableView(error, systemImage: "wifi.exclamationmark")
                    } else if !loading && filtered.isEmpty {
                        ContentUnavailableView("Geen kortingsbonnen beschikbaar", systemImage: "ticket")
                    }
                    ForEach(filtered) { coupon in
                        VStack(alignment: .leading, spacing: 12) {
                            PasrDiscountCard(business: coupon.business, title: coupon.title,
                                discount: coupon.discount, kind: coupon.isPromo ? "Actiecode" : "Kortingscoupon",
                                logo: coupon.logo, color: coupon.color, state: .available, expires: coupon.end)
                            if !coupon.text.isEmpty { Text(coupon.text).font(.subheadline) }
                            Text("Vanaf \(coupon.minimum.formatted(.currency(code: "EUR")))")
                                .font(.caption)
                            Button(coupon.isPromo ? "Bewaar actiecode in Pasr" : "Bewaar kortingsbon") {
                                Task { await claim(coupon) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.iris)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Kortingsbonnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Zoek aanbieding of winkel")
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $selected) { claim in
                NavigationStack {
                    VStack(spacing: 18) {
                        Text(claim.business).font(.headline)
                        Text(claim.title).font(.title2.bold())
                        if claim.redeemed {
                            Label("PASR · GEBRUIKT · Deze aanbieding is al verzilverd", systemImage: "checkmark.seal.fill")
                        } else if claim.disabled || (claim.end ?? .distantFuture) < .now {
                            Label("Deze aanbieding is niet meer geldig", systemImage: "lock.fill")
                        } else if let code = claim.code, let qr = qrImage(code) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 250, height: 250)
                                .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }
                        if !claim.redeemed && !claim.disabled, let code = claim.code {
                            Text(code).font(.footnote.monospaced()).textSelection(.enabled)
                        }
                        Text("Laat deze code bij de kassa scannen. Alleen de ondernemer kan de bon verzilveren.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(25)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.ink.ignoresSafeArea())
                    .navigationTitle("Mijn kortingsbon")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Sluiten") { selected = nil }
                    } }
                }
            }
            .alert("Kortingsbon", isPresented: Binding(get: { error != nil && !items.isEmpty }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func qrImage(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 9, y: 9)),
                                                       from: output.extent.applying(CGAffineTransform(scaleX: 9, y: 9))) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let data = try await AccountService.shared.publicRPC("pasr_business_coupon_list", body: [:])
            let merchantOffers = (data as? [[String: Any]] ?? []).compactMap(Coupon.init)
            let promos = try await AccountService.shared.publicRPC("pasr_business_promo_public", body: [:])
            let promoOffers = (promos as? [[String: Any]] ?? []).map { row -> [String: Any] in
                var result = row; result["kind"] = "code"; return result
            }.compactMap(Coupon.init)
            items = merchantOffers + promoOffers
            if AccountService.shared.isSignedIn {
                let mine = try await AccountService.shared.rpc("pasr_business_coupon_mine", body: [:])
                let promoMine = try await AccountService.shared.rpc("pasr_business_promo_mine", body: [:])
                let promoClaims = (promoMine as? [[String: Any]] ?? []).map { row -> [String: Any] in
                    var result = row; result["kind"] = "code"; return result
                }
                saved = ((mine as? [[String: Any]] ?? []) + promoClaims).compactMap(Claim.init)
            }
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func claim(_ coupon: Coupon) async {
        guard AccountService.shared.isSignedIn else {
            error = "Log eerst in met je Pasr-account via Instellingen om deze bon op te slaan."
            return
        }
        do {
            let data = try await AccountService.shared.rpc(coupon.isPromo ? "pasr_business_promo_claim" : "pasr_business_coupon_claim",
                body: [coupon.isPromo ? "p_promo" : "p_coupon": coupon.id])
            if let j = data as? [String: Any] {
                let claim = Claim(["code":j["code"] ?? NSNull(),"id":j["id"] ?? coupon.id,"title":coupon.title,
                                   "business":coupon.business,"redeemed":j["redeemed"] ?? false,
                                   "discount_value":coupon.amount,"discount_type":coupon.kind,
                                   "logo":coupon.logo ?? "", "color":coupon.color,
                                   "kind":coupon.isPromo ? "code" : "coupon"])
                selected = claim
                await load()
            }
        } catch { self.error = error.localizedDescription }
    }
}
