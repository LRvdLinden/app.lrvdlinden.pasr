import SwiftUI

/// Dezelfde Pasr-kaarttaal als de stempelkaart: echte zaaklogo's, eigen kleur, pasr. en status op de voorzijde.
struct PasrDiscountCard: View {
    let business: String
    let title: String
    let discount: String
    let kind: String
    let logo: String?
    let color: String
    let state: State
    let expires: Date?

    enum State { case available, saved, used, expired, paused, exhausted }
    private var inactive: Bool { state == .used || state == .expired || state == .paused || state == .exhausted }
    private var background: Color {
        let hex = color.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count == 7, hex.first == "#",
              let rgb = Int(hex.dropFirst(), radix: 16) else { return Color(red: 0.416, green: 0.361, blue: 1) }
        return Color(red: Double((rgb >> 16) & 255)/255,
                     green: Double((rgb >> 8) & 255)/255,
                     blue: Double(rgb & 255)/255)
    }
    private var merchantLogo: UIImage? {
        guard let logo, let raw = Data(base64Encoded: logo) else { return nil }
        return UIImage(data: raw)
    }
    private var stateText: String {
        switch state {
        case .available: "Beschikbaar"
        case .saved: "Opgeslagen"
        case .used: "GEBRUIKT"
        case .expired: "VERLOPEN"
        case .paused: "GEPAUZEERD"
        case .exhausted: "OPGEBRUIKT"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Group {
                    if let image = merchantLogo {
                        Image(uiImage: image).resizable().scaledToFit().padding(4)
                    } else {
                        Text(String(business.prefix(1)).uppercased()).font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 46, height: 46)
                .background(.white, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(business).font(.headline).lineLimit(1)
                    Text(kind).font(.caption).opacity(0.85)
                }
                Spacer(minLength: 6)
                Text("pasr.").font(.system(size: 23, weight: .heavy, design: .rounded))
            }
            Text(discount).font(.system(size: 34, weight: .heavy, design: .rounded)).minimumScaleFactor(0.65).lineLimit(1)
            Text(title).font(.headline).lineLimit(2)
            HStack {
                Label(stateText, systemImage: inactive ? "checkmark.seal.fill" : "checkmark.circle.fill")
                    .font(.caption.bold())
                Spacer()
                if let expires { Text("t/m \(expires.formatted(date: .numeric, time: .omitted))").font(.caption) }
            }
            .padding(.top, 5)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 215, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 23)
                .fill(LinearGradient(colors: inactive ? [.gray.opacity(0.9), .gray] :
                    [background.opacity(0.84), background], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            if inactive {
                RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.17))
            }
        }
        .overlay(alignment: .center) {
            if state == .used {
                Text("PASR · GEBRUIKT")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(2).padding(14)
                    .overlay(Capsule().stroke(.white, lineWidth: 3))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-16))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(business), \(kind), \(discount), \(title), \(stateText)")
    }
}
