import SwiftUI

/// Visuele Pasr-coupon/code voor de ondernemer, in de stijl van de bestaande stempelkaart.
struct BusinessDiscountCard: View {
    let business: String
    let title: String
    let discountType: String
    let discountValue: Double
    let color: String
    let logo: String?
    let kind: String
    let status: String
    let usage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let image = LogoImage.image(logo) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: 42, height: 42)
                        .background(.white, in: RoundedRectangle(cornerRadius: 9))
                } else {
                    Text(String(business.prefix(1))).font(.title2.bold())
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
                }
                VStack(alignment: .leading) {
                    Text(business).font(.headline)
                    Text(kind).font(.caption).opacity(0.8)
                }
                Spacer()
                Text("pasr.").font(.title2.bold())
            }
            Text(discountType == "percent" ? "\(discountValue.formatted())% KORTING" :
                    "\(discountValue.formatted(.currency(code: "EUR"))) KORTING")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text(title).font(.headline)
            HStack {
                Label(status, systemImage: status == "Actief" ? "checkmark.circle.fill" : "seal.fill")
                Spacer()
                Text(usage)
            }.font(.caption.bold())
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Color(hex: color), in: RoundedRectangle(cornerRadius: 22))
        .opacity(status == "Verwijderd" || status == "Gepauzeerd" ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }
}
