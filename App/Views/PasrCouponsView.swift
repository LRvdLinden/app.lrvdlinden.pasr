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

        init?(_ json: [String: Any]) {
            guard let id = json["id"] as? String,
                  let title = json["title"] as? String else { return nil }
            self.id = id
            self.title = title
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
        let code: String
        let title: String
        let business: String
        let redeemed: Bool

        init?(_ json: [String: Any]) {
            guard let code = json["code"] as? String else { return nil }
            self.id = json["id"] as? String ?? code
            self.code = code
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
                                HStack {
                                    Image(systemName: "ticket.fill").foregroundStyle(Brand.iris)
                                    VStack(alignment: .leading) {
                                        Text(claim.title).font(.headline)
                                        Text(claim.business).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(claim.redeemed ? "Gebruikt" : "Bekijken")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(16).background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 18))
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
                            HStack {
                                Text(coupon.business).font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "ticket.fill")
                            }
                            Text(coupon.discount)
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                            Text(coupon.title).font(.headline)
                            if !coupon.text.isEmpty { Text(coupon.text).font(.subheadline) }
                            Text("Vanaf \(coupon.minimum.formatted(.currency(code: "EUR")))")
                                .font(.caption)
                            Button("Bewaar kortingsbon") {
                                Task { await claim(coupon) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.iris)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 22))
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
                            Label("Deze bon is al gebruikt", systemImage: "checkmark.seal.fill")
                        } else if let qr = qrImage(claim.code) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 250, height: 250)
                                .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }
                        Text(claim.code).font(.footnote.monospaced()).textSelection(.enabled)
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
            items = (data as? [[String: Any]] ?? []).compactMap(Coupon.init)
            if AccountService.shared.isSignedIn {
                let mine = try await AccountService.shared.rpc("pasr_business_coupon_mine", body: [:])
                saved = (mine as? [[String: Any]] ?? []).compactMap(Claim.init)
            }
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func claim(_ coupon: Coupon) async {
        guard AccountService.shared.isSignedIn else {
            error = "Log eerst in met je Pasr-account via Instellingen om deze bon op te slaan."
            return
        }
        do {
            let data = try await AccountService.shared.rpc("pasr_business_coupon_claim", body: ["p_coupon": coupon.id])
            if let j = data as? [String: Any], let code = j["code"] as? String {
                let claim = Claim(["code":code,"id":j["id"] ?? code,"title":coupon.title,
                                   "business":coupon.business,"redeemed":j["redeemed"] ?? false])
                selected = claim
                await load()
            }
        } catch { self.error = error.localizedDescription }
    }
}
