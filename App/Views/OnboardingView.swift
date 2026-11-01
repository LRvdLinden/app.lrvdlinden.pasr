import SwiftUI

/// Welcome screens the first time Pasr opens: what the app does, then an optional account.
struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0
    @State private var accountMode: AccountSheet.Mode?

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(id: 0, symbol: "wallet.pass", title: "Al je pasjes op één plek",
             text: "Klantenkaarten, spaarpassen en cadeaukaarten van ruim 300 Nederlandse winkels, met hun echte logo en kleur."),
        Page(id: 1, symbol: "barcode.viewfinder", title: "Scannen en klaar",
             text: "Kies de winkel en scan de barcode. Of zet je kaarten uit Klarna of Stocard over met een paar screenshots."),
        Page(id: 2, symbol: "applewatch", title: "Altijd bij de hand",
             text: "Bij de kassa tik je de kaart aan en draait hij om naar de barcode. Ook op je Apple Watch, in widgets en op je Mac."),
        Page(id: 3, symbol: "lock.shield", title: "Veilig en privé",
             text: "Kaartnummers staan versleuteld. Vergrendel Pasr of losse kaarten met Face ID. Geen reclame, geen tracking."),
    ]

    private var isLast: Bool { page == pages.count }

    var body: some View {
        ZStack {
            Brand.ink.ignoresSafeArea()
            RadialGradient(colors: [Brand.iris.opacity(0.35), .clear], center: .top, startRadius: 10, endRadius: 520)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !isLast {
                        Button("Sla over") { withAnimation { page = pages.count } }
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 24)

                TabView(selection: $page) {
                    ForEach(pages) { p in
                        pageView(p).tag(p.id)
                    }
                    accountPage.tag(pages.count)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif

                dots.padding(.vertical, 18)

                if !isLast {
                    Button {
                        withAnimation(.snappy) { page += 1 }
                    } label: {
                        Text("Volgende").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.iris)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: 560)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $accountMode) { mode in
            AccountSheet(mode: mode) { onFinish() }
        }
    }

    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            illustration(for: p)
                .frame(height: 230)
            VStack(spacing: 12) {
                Text(p.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(p.text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
    }

    /// Page 1 shows three real cards fanned out; the others a large symbol on a glowing tile.
    @ViewBuilder private func illustration(for p: Page) -> some View {
        if p.id == 0 {
            ZStack {
                ForEach(Array(["jumbo", "hema", "ah"].enumerated()), id: \.offset) { index, id in
                    if let t = StoreTemplates.template(id: id) {
                        sampleCard(t)
                            .frame(width: 220, height: 220 / Brand.cardAspect)
                            .rotationEffect(.degrees(Double(index - 1) * 9))
                            .offset(x: CGFloat(index - 1) * 34, y: CGFloat(abs(index - 1)) * 10)
                    }
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(LinearGradient(colors: [Brand.iris, Brand.iris.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 150, height: 150)
                .overlay {
                    Image(systemName: p.symbol)
                        .font(.system(size: 66, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }
                .shadow(color: Brand.iris.opacity(0.5), radius: 30, y: 12)
        }
    }

    private func sampleCard(_ t: StoreTemplate) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(hex: t.cardHex))
            .overlay {
                if let data = LogoService.bundledLogo(for: t.domain) {
                    StoreLogoMark(data: data, style: StoreLogoStyles.style(for: t.domain), height: 46, maxWidth: 140)
                } else {
                    Text(t.name).font(.title3.bold()).foregroundStyle(Color.onCard(t.cardHex))
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
    }

    private var accountPage: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Brand.gradient)
            VStack(spacing: 12) {
                Text("Bewaar je kaarten in een account")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Gratis en optioneel. Je kaarten staan dan versleuteld op één plek en zijn er meteen weer op een nieuwe telefoon.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                if AccountConfig.isConfigured {
                    Button { accountMode = .signUp } label: {
                        Text("Maak een account").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.iris)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button { accountMode = .signIn } label: {
                        Text("Ik heb al een account").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered).tint(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button(AccountConfig.isConfigured ? "Ga verder zonder account" : "Aan de slag") { onFinish() }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0...pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Brand.iris : Color.white.opacity(0.25))
                    .frame(width: i == page ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: page)
    }
}

extension AccountSheet.Mode: Identifiable {
    var id: Self { self }
}
